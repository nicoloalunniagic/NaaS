// Centralized API client. Base URL configurable via VITE_API_BASE_URL.
// Empty string means same-origin (used in dev via Vite proxy and in prod
// when SWA's `routes` proxy /api -> Container Apps).
const API_BASE = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '')

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

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	const res = await fetch(`${API_BASE}${path}`, {
		headers: { 'Content-Type': 'application/json' },
		...init
	})
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
