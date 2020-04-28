import React from 'react'
import { ToastProvider } from 'react-toast-notifications'

import { Header } from '../components/header.component'
import { Balances } from '../components/balances.component'
import { Markets } from '../components/markets.component'

import { accountContext } from '../state/account.context'
import { useAccount } from '../hooks/account.hook'

export const HomePage = () => {
  const account = useAccount()

  return (
    <ToastProvider>
      <accountContext.Provider value={account}>
        <Header />
        <div className="container" style={{ marginTop: '60px' }}>
          <Balances />
          <Markets />
        </div>
      </accountContext.Provider>
    </ToastProvider>
  )
}
