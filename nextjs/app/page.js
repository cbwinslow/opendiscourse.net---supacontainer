'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { createClient } from '@/utils/supabase/client'

export default function Home() {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const supabase = createClient()

  useEffect(() => {
    const getUser = async () => {
      const { data: { user } } = await supabase.auth.getUser()
      setUser(user)
      setLoading(false)
    }

    getUser()

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user || null)
      setLoading(false)
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto py-12 px-4 sm:px-6 lg:px-8">
        <div className="text-center">
          <h1 className="text-4xl font-extrabold text-gray-900 sm:text-5xl sm:tracking-tight lg:text-6xl">
            OpenDiscourse
          </h1>
          <p className="mt-6 max-w-lg mx-auto text-xl text-gray-500">
            A powerful platform for discourse analysis and AI-powered content processing
          </p>
          <div className="mt-10 flex justify-center">
            {user ? (
              <div className="space-y-4">
                <p className="text-lg text-gray-700">
                  Welcome back, {user.email}!
                </p>
                <div className="flex space-x-4">
                  <Link href="/account">
                    <span className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                      Account
                    </span>
                  </Link>
                  <button
                    onClick={async () => {
                      await supabase.auth.signOut()
                    }}
                    className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                  >
                    Sign out
                  </button>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <p className="text-lg text-gray-700">
                  Get started by signing in or creating an account
                </p>
                <div className="flex space-x-4 justify-center">
                  <Link href="/login">
                    <span className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                      Sign in
                    </span>
                  </Link>
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="mt-16">
          <div className="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3">
            <div className="bg-white overflow-hidden shadow rounded-lg">
              <div className="px-4 py-5 sm:p-6">
                <h3 className="text-lg font-medium text-gray-900">Document Processing</h3>
                <p className="mt-2 text-gray-500">
                  Process and analyze documents with our advanced AI tools
                </p>
              </div>
            </div>
            <div className="bg-white overflow-hidden shadow rounded-lg">
              <div className="px-4 py-5 sm:p-6">
                <h3 className="text-lg font-medium text-gray-900">Knowledge Graph</h3>
                <p className="mt-2 text-gray-500">
                  Build and explore knowledge graphs from your content
                </p>
              </div>
            </div>
            <div className="bg-white overflow-hidden shadow rounded-lg">
              <div className="px-4 py-5 sm:p-6">
                <h3 className="text-lg font-medium text-gray-900">AI Assistants</h3>
                <p className="mt-2 text-gray-500">
                  Interact with AI assistants for enhanced productivity
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}