import { useEffect, useState } from 'react'
import { api, type Customer, type Project, type ProjectInput } from '../api'

const empty: ProjectInput = { name: '', description: '', customerId: 0 }

export default function ProjectsPage() {
	const [items, setItems] = useState<Project[]>([])
	const [customers, setCustomers] = useState<Customer[]>([])
	const [editing, setEditing] = useState<Project | null>(null)
	const [form, setForm] = useState<ProjectInput>(empty)
	const [error, setError] = useState<string | null>(null)

	async function reload() {
		try {
			const [p, c] = await Promise.all([
				api.projects.list(),
				api.customers.list()
			])
			setItems(p)
			setCustomers(c)
			if (!editing && c.length > 0 && form.customerId === 0) {
				setForm(f => ({ ...f, customerId: c[0].id }))
			}
		} catch (e) {
			setError((e as Error).message)
		}
	}

	useEffect(() => {
		void reload()
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [])

	async function submit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		try {
			if (editing) {
				await api.projects.update(editing.id, form)
			} else {
				await api.projects.create(form)
			}
			setEditing(null)
			setForm({ ...empty, customerId: customers[0]?.id ?? 0 })
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	async function remove(id: number) {
		if (!confirm('Delete this project?')) return
		try {
			await api.projects.remove(id)
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	function startEdit(p: Project) {
		setEditing(p)
		setForm({
			name: p.name,
			description: p.description ?? '',
			customerId: p.customerId
		})
	}

	function cancelEdit() {
		setEditing(null)
		setForm({ ...empty, customerId: customers[0]?.id ?? 0 })
	}

	function customerName(id: number) {
		return customers.find(c => c.id === id)?.name ?? `#${id}`
	}

	return (
		<>
			<h1>Projects</h1>
			{error && <div className='error'>{error}</div>}

			{customers.length === 0 ? (
				<p className='muted'>
					Create at least one customer before adding projects.
				</p>
			) : (
				<form className='stack' onSubmit={submit}>
					<h3>{editing ? `Edit project #${editing.id}` : 'New project'}</h3>
					<label>
						Customer
						<select
							value={form.customerId}
							onChange={e =>
								setForm({ ...form, customerId: Number(e.target.value) })
							}
						>
							{customers.map(c => (
								<option key={c.id} value={c.id}>
									{c.name} (#{c.id})
								</option>
							))}
						</select>
					</label>
					<label>
						Name
						<input
							required
							value={form.name}
							onChange={e => setForm({ ...form, name: e.target.value })}
						/>
					</label>
					<label>
						Description
						<textarea
							rows={3}
							value={form.description ?? ''}
							onChange={e => setForm({ ...form, description: e.target.value })}
						/>
					</label>
					<div className='actions'>
						<button type='submit' className='primary'>
							{editing ? 'Save' : 'Create'}
						</button>
						{editing && (
							<button type='button' onClick={cancelEdit}>
								Cancel
							</button>
						)}
					</div>
				</form>
			)}

			<div className='toolbar'>
				<button onClick={reload}>Refresh</button>
				<span className='muted'>{items.length} project(s)</span>
			</div>

			<table>
				<thead>
					<tr>
						<th>ID</th>
						<th>Name</th>
						<th>Customer</th>
						<th>Description</th>
						<th>Created</th>
						<th></th>
					</tr>
				</thead>
				<tbody>
					{items.map(p => (
						<tr key={p.id}>
							<td>{p.id}</td>
							<td>{p.name}</td>
							<td>{customerName(p.customerId)}</td>
							<td>{p.description ?? '—'}</td>
							<td>{new Date(p.createdAt).toLocaleString()}</td>
							<td className='actions'>
								<button onClick={() => startEdit(p)}>Edit</button>
								<button className='danger' onClick={() => remove(p.id)}>
									Delete
								</button>
							</td>
						</tr>
					))}
					{items.length === 0 && (
						<tr>
							<td colSpan={6} className='muted'>
								No projects yet.
							</td>
						</tr>
					)}
				</tbody>
			</table>
		</>
	)
}
