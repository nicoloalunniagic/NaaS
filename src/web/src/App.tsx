import { useState, useEffect } from 'react'
import { NavLink, Route, Routes, Navigate } from 'react-router-dom'
import CustomersPage from './pages/CustomersPage'
import CustomerDetailPage from './pages/CustomerDetailPage'
import ProjectsPage from './pages/ProjectsPage'
import { api, getAuthToken, setAuthToken } from './api'

// VAPT Lab Mode flag — set VITE_ENABLE_VAPT_LAB_MODE=true in .env.local to enable.
const VAPT_LAB_MODE = import.meta.env.VITE_ENABLE_VAPT_LAB_MODE === 'true'

export default function App() {
	const [token, setToken] = useState<string | null>(getAuthToken())

	if (!token) {
		return (
			<div className='layout'>
				{VAPT_LAB_MODE && (
					<div
						style={{
							background: '#b91c1c',
							color: '#fff',
							padding: '8px 16px',
							fontWeight: 'bold',
							textAlign: 'center',
							letterSpacing: '0.05em'
						}}
					>
						⚠ VAPT LAB MODE ENABLED — intentionally vulnerable — DO NOT use in
						production
					</div>
				)}
				<AuthPage
					onAuthenticated={jwt => {
						setAuthToken(jwt)
						setToken(jwt)
					}}
				/>
			</div>
		)
	}

	return (
		<>
			{VAPT_LAB_MODE && (
				<div
					style={{
						background: '#b91c1c',
						color: '#fff',
						padding: '8px 16px',
						fontWeight: 'bold',
						textAlign: 'center',
						letterSpacing: '0.05em'
					}}
				>
					⚠ VAPT LAB MODE ENABLED — intentionally vulnerable — DO NOT use in
					production
				</div>
			)}
			<nav className='top'>
				<strong>NaaS Admin</strong>
				<NavLink to='/customers'>Customers</NavLink>
				<NavLink to='/projects'>Projects</NavLink>
				<button
					type='button'
					onClick={() => {
						setAuthToken(null)
						setToken(null)
					}}
				>
					Logout
				</button>
			</nav>
			<div className='layout'>
				<Routes>
					<Route path='/' element={<Navigate to='/customers' replace />} />
					<Route path='/customers' element={<CustomersPage />} />
					<Route path='/customers/:id' element={<CustomerDetailPage />} />
					<Route path='/projects' element={<ProjectsPage />} />
					<Route path='*' element={<p>Not found.</p>} />
				</Routes>
			</div>
		</>
	)
}

type AuthMode = 'login' | 'register'

function AuthPage({
	onAuthenticated
}: {
	onAuthenticated: (token: string) => void
}) {
	const [mode, setMode] = useState<AuthMode>('login')
	const [username, setUsername] = useState('')
	const [password, setPassword] = useState('')
	const [confirmPassword, setConfirmPassword] = useState('')
	const [error, setError] = useState<string | null>(null)
	const [loading, setLoading] = useState(false)

	useEffect(() => {
		setUsername('')
		setPassword('')
		setConfirmPassword('')
		setError(null)
	}, [mode])

	async function submit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)

		if (mode === 'register' && password !== confirmPassword) {
			setError('Passwords do not match.')
			return
		}

		setLoading(true)
		try {
			if (mode === 'register') {
				await api.auth.register({ username, password })
			}
			const login = await api.auth.login({ username, password })
			onAuthenticated(login.token)
		} catch (e) {
			setError((e as Error).message)
		} finally {
			setLoading(false)
		}
	}

	return (
		<div className='auth-card'>
			<h1>NaaS Admin</h1>
			<p className='muted'>
				Login o registrazione obbligatori prima di gestire clienti e progetti.
			</p>
			<div className='actions'>
				<button
					type='button'
					className={mode === 'login' ? 'primary' : ''}
					onClick={() => setMode('login')}
				>
					Login
				</button>
				<button
					type='button'
					className={mode === 'register' ? 'primary' : ''}
					onClick={() => setMode('register')}
				>
					Register
				</button>
			</div>

			<form className='stack' onSubmit={submit}>
				<label>
					Username
					<input
						required
						minLength={3}
						maxLength={64}
						value={username}
						onChange={e => setUsername(e.target.value)}
					/>
				</label>
				<label>
					Password
					<input
						required
						type='password'
						minLength={12}
						value={password}
						onChange={e => setPassword(e.target.value)}
					/>
				</label>
				{mode === 'register' && (
					<label>
						Confirm password
						<input
							required
							type='password'
							minLength={12}
							value={confirmPassword}
							onChange={e => setConfirmPassword(e.target.value)}
						/>
					</label>
				)}
				{error && <div className='error'>{error}</div>}
				<button type='submit' className='primary' disabled={loading}>
					{loading
						? 'Please wait...'
						: mode === 'login'
							? 'Login'
							: 'Register and login'}
				</button>
			</form>
		</div>
	)
}
