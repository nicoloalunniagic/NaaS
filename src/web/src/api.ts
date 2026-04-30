// Centralized API client. Base URL configurable via VITE_API_BASE_URL.
// Empty string means same-origin (used in dev via Vite proxy and in prod
// when SWA's `routes` proxy /api -> Container Apps).
const API_BASE = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '')
const TOKEN_STORAGE_KEY = 'naas_auth_token'

let authToken: string | null = localStorage.getItem(TOKEN_STORAGE_KEY)

export function setAuthToken(token: string | null) {
	authToken = token
	if (token) {
		localStorage.setItem(TOKEN_STORAGE_KEY, token)
	} else {
		localStorage.removeItem(TOKEN_STORAGE_KEY)
	}
}

export function getAuthToken() {
	return authToken
}

export interface Customer {
	id: number
	name: string
	email: string | null
	codiceFiscale: string
	createdAt: string
	projects?: Project[]
}

export interface Project {
	id: number
	name: string
	description: string | null
	createdAt: string
	customerId: number
}

export interface CustomerInput {
	name: string
	email?: string | null
	codiceFiscale: string
}

export interface ProjectInput {
	name: string
	description?: string | null
	customerId: number
}

export interface AuthRequest {
	username: string
	password: string
}

export interface AuthResponse {
	token: string
	expiresAt: string
	username: string
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	const headers = new Headers(init?.headers)
	headers.set('Content-Type', 'application/json')
	if (authToken) {
		headers.set('Authorization', `Bearer ${authToken}`)
	}

	const res = await fetch(`${API_BASE}${path}`, {
		headers,
		...init
	})

	if (res.status === 401) {
		throw new Error('Session expired or unauthorized. Please login again.')
	}

	if (!res.ok) {
		let message = `HTTP ${res.status}`
		try {
			const body = await res.json()
			if (body?.message) message = body.message
		} catch {
			// body is not JSON, keep generic message
		}
		throw new Error(message)
	}
	if (res.status === 204) return undefined as T
	return (await res.json()) as T
}

export const api = {
	auth: {
		register: (input: AuthRequest) =>
			request<void>('/auth/register', {
				method: 'POST',
				body: JSON.stringify(input)
			}),
		login: (input: AuthRequest) =>
			request<AuthResponse>('/auth/login', {
				method: 'POST',
				body: JSON.stringify(input)
			})
	},
	customers: {
		list: () => request<Customer[]>('/customers'),
		get: (id: number) => request<Customer>(`/customers/${id}`),
		create: (input: CustomerInput) =>
			request<Customer>('/customers', {
				method: 'POST',
				body: JSON.stringify(input)
			}),
		update: (id: number, input: CustomerInput) =>
			request<Customer>(`/customers/${id}`, {
				method: 'PUT',
				body: JSON.stringify(input)
			}),
		remove: (id: number) =>
			request<void>(`/customers/${id}`, { method: 'DELETE' }),
		projects: (id: number) => request<Project[]>(`/customers/${id}/projects`)
	},
	projects: {
		list: () => request<Project[]>('/projects'),
		get: (id: number) => request<Project>(`/projects/${id}`),
		create: (input: ProjectInput) =>
			request<Project>('/projects', {
				method: 'POST',
				body: JSON.stringify(input)
			}),
		update: (id: number, input: ProjectInput) =>
			request<Project>(`/projects/${id}`, {
				method: 'PUT',
				body: JSON.stringify(input)
			}),
		remove: (id: number) =>
			request<void>(`/projects/${id}`, { method: 'DELETE' })
	}
}
