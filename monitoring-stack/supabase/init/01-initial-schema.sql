-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create custom types
CREATE TYPE resource_type AS ENUM ('cpu', 'gpu', 'memory', 'storage', 'network');
CREATE TYPE metric_type AS ENUM ('gauge', 'counter', 'histogram', 'summary');

-- Create tables
CREATE TABLE IF NOT EXISTS public.agents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'offline',
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS public.agent_capabilities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    parameters JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(agent_id, name)
);

CREATE TABLE IF NOT EXISTS public.agent_resources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    type resource_type NOT NULL,
    capacity FLOAT NOT NULL,
    used FLOAT DEFAULT 0,
    unit TEXT NOT NULL,
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(agent_id, name)
);

CREATE TABLE IF NOT EXISTS public.agent_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type metric_type NOT NULL,
    value FLOAT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    labels JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_agent_metrics_agent_id ON public.agent_metrics(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_metrics_name ON public.agent_metrics(name);
CREATE INDEX IF NOT EXISTS idx_agent_metrics_timestamp ON public.agent_metrics(timestamp);

-- Create a hypertable for time-series metrics
CREATE OR REPLACE FUNCTION create_hypertable_if_not_exists()
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM _timescaledb_catalog.hypertable WHERE table_name = 'agent_metrics') THEN
        PERFORM create_hypertable('agent_metrics', 'timestamp', if_not_exists => TRUE);
    END IF;
END;
$$ LANGUAGE plpgsql;

SELECT create_hypertable_if_not_exists();

-- Create a function to update the updated_at column
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER update_agents_modtime
BEFORE UPDATE ON public.agents
FOR EACH ROW EXECUTE FUNCTION update_modified_column();

CREATE TRIGGER update_agent_capabilities_modtime
BEFORE UPDATE ON public.agent_capabilities
FOR EACH ROW EXECUTE FUNCTION update_modified_column();

CREATE TRIGGER update_agent_resources_modtime
BEFORE UPDATE ON public.agent_resources
FOR EACH ROW EXECUTE FUNCTION update_modified_column();

-- Create RLS (Row Level Security) policies
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_metrics ENABLE ROW LEVEL SECURITY;

-- Create roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOINHERIT BYPASSRLS;
    END IF;
    
    -- Grant usage on schema
    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
    
    -- Grant permissions on tables
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
    GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
    
    -- Grant usage on sequences
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
    
    -- Grant execute on functions
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
END
$$;

-- Set up RLS policies
-- Agents
CREATE POLICY "Enable read access for all users"
    ON public.agents
    FOR SELECT
    USING (true);

CREATE POLICY "Enable insert for authenticated users only"
    ON public.agents
    FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Agent Capabilities
CREATE POLICY "Enable read access for all users on capabilities"
    ON public.agent_capabilities
    FOR SELECT
    USING (true);

CREATE POLICY "Enable insert for authenticated users on capabilities"
    ON public.agent_capabilities
    FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Agent Resources
CREATE POLICY "Enable read access for all users on resources"
    ON public.agent_resources
    FOR SELECT
    USING (true);

CREATE POLICY "Enable insert for authenticated users on resources"
    ON public.agent_resources
    FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Agent Metrics
CREATE POLICY "Enable read access for all users on metrics"
    ON public.agent_metrics
    FOR SELECT
    USING (true);

CREATE POLICY "Enable insert for authenticated users on metrics"
    ON public.agent_metrics
    FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Create storage bucket for agent data
INSERT INTO storage.buckets (id, name, public)
VALUES ('agent-data', 'agent-data', false)
ON CONFLICT (id) DO NOTHING;

-- Set up storage policies
CREATE POLICY "Agent data access"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'agent-data' AND (auth.role() = 'authenticated'));

CREATE POLICY "Agent data upload"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id = 'agent-data' AND (auth.role() = 'authenticated'));

-- Create a view for agent status
CREATE OR REPLACE VIEW public.agent_status AS
SELECT 
    a.id,
    a.name,
    a.status,
    a.last_seen_at,
    jsonb_agg(DISTINCT jsonb_build_object(
        'name', ac.name,
        'description', ac.description,
        'is_active', ac.is_active
    )) AS capabilities,
    jsonb_agg(DISTINCT jsonb_build_object(
        'name', ar.name,
        'type', ar.type,
        'used', ar.used,
        'capacity', ar.capacity,
        'unit', ar.unit,
        'utilization', (ar.used / NULLIF(ar.capacity, 0)) * 100
    )) AS resources
FROM 
    public.agents a
LEFT JOIN 
    public.agent_capabilities ac ON a.id = ac.agent_id
LEFT JOIN 
    public.agent_resources ar ON a.id = ar.agent_id
GROUP BY 
    a.id, a.name, a.status, a.last_seen_at;

-- Create a function to get agent metrics
CREATE OR REPLACE FUNCTION public.get_agent_metrics(
    p_agent_id UUID,
    p_metric_name TEXT DEFAULT NULL,
    p_start_time TIMESTAMPTZ DEFAULT NOW() - INTERVAL '24 hours',
    p_end_time TIMESTAMPTZ DEFAULT NOW(),
    p_limit INT DEFAULT 1000
)
RETURNS TABLE (
    id UUID,
    agent_id UUID,
    name TEXT,
    type TEXT,
    value FLOAT,
    timestamp TIMESTAMPTZ,
    labels JSONB
)
LANGUAGE sql
AS $$
    SELECT 
        id,
        agent_id,
        name,
        type::TEXT,
        value,
        timestamp,
        labels
    FROM 
        public.agent_metrics
    WHERE 
        agent_id = p_agent_id
        AND (p_metric_name IS NULL OR name = p_metric_name)
        AND timestamp BETWEEN p_start_time AND p_end_time
    ORDER BY 
        timestamp DESC
    LIMIT 
        p_limit;
$$;

-- Create a function to get resource utilization
CREATE OR REPLACE FUNCTION public.get_resource_utilization(
    p_resource_type TEXT DEFAULT NULL
)
RETURNS TABLE (
    resource_type TEXT,
    total_capacity FLOAT,
    total_used FLOAT,
    utilization_pct FLOAT,
    available_agents BIGINT
)
LANGUAGE sql
AS $$
    SELECT 
        COALESCE(p_resource_type, ar.type::TEXT) AS resource_type,
        SUM(ar.capacity) AS total_capacity,
        SUM(ar.used) AS total_used,
        CASE 
            WHEN SUM(ar.capacity) > 0 THEN (SUM(ar.used) / SUM(ar.capacity)) * 100 
            ELSE 0 
        END AS utilization_pct,
        COUNT(DISTINCT a.id) FILTER (WHERE a.status = 'online') AS available_agents
    FROM 
        public.agent_resources ar
    JOIN 
        public.agents a ON ar.agent_id = a.id
    WHERE 
        (p_resource_type IS NULL OR ar.type = p_resource_type::resource_type)
        AND ar.is_available = true
    GROUP BY 
        ROLLUP(ar.type)
    HAVING 
        ar.type IS NOT NULL OR p_resource_type IS NULL;
$$;
