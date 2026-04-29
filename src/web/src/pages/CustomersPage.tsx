import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api, type Customer, type CustomerInput } from '../api'

const empty: CustomerInput = { name: '', email: '' }

export default function CustomersPage() {
	const [items, setItems] = useState<Customer[]>([])
	const [editing, setEditing] = useState<Customer | null>(null)
	const [form, setForm] = useState<CustomerInput>(empty)
	const [error, setError] = useState<string | null>(null)
	const [loading, setLoading] = useState(false)

	async function reload() {
		setLoading(true)
		setError(null)
		try {
			setItems(await api.customers.list())
		} catch (e) {
			setError((e as Error).message)
		} finally {
			setLoading(false)
		}
	}

	useEffect(() => {
		void reload()
	}, [])

	async function submit(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		try {
			if (editing) {
				await api.customers.update(editing.id, form)
			} else {
				await api.customers.create(form)
			}
			setEditing(null)
			setForm(empty)
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	async function remove(id: number) {
		if (!confirm('Delete this customer? Linked projects will be removed too.'))
			return
		try {
			await api.customers.remove(id)
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	function startEdit(c: Customer) {
		setEditing(c)
		setForm({ name: c.name, email: c.email ?? '' })
	}

	function cancelEdit() {
		setEditing(null)
		setForm(empty)
	}

	return (
		<>
			<h1>Customers</h1>
			{error && <div className='error'>{error}</div>}

			<form className='stack' onSubmit={submit}>
				<h3>{editing ? `Edit customer #${editing.id}` : 'New customer'}</h3>
				<label>
					Name
					<input
						required
						value={form.name}
						onChange={e => setForm({ ...form, name: e.target.value })}
					/>
				</label>
				<label>
					Email
					<input
						type='email'
						value={form.email ?? ''}
						onChange={e => setForm({ ...form, email: e.target.value })}
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

			<div className='toolbar'>
				<button onClick={reload} disabled={loading}>
					Refresh
				</button>
				<span className='muted'>{items.length} customer(s)</span>
			</div>

			<table>
				<thead>
					<tr>
						<th>ID</th>
						<th>Name</th>
						<th>Email</th>
						<th>Created</th>
						<th></th>
					</tr>
				</thead>
				<tbody>
					{items.map(c => (
						<tr key={c.id}>
							<td>{c.id}</td>
							<td>
								<Link to={`/customers/${c.id}`}>{c.name}</Link>
							</td>
							<td>{c.email ?? '—'}</td>
							<td>{new Date(c.createdAt).toLocaleString()}</td>
							<td className='actions'>
								<button onClick={() => startEdit(c)}>Edit</button>
								<button className='danger' onClick={() => remove(c.id)}>
									Delete
								</button>
							</td>
						</tr>
					))}
					{items.length === 0 && !loading && (
						<tr>
							<td colSpan={5} className='muted'>
								No customers yet.
							</td>
						</tr>
					)}
				</tbody>
			</table>
		</>
	)
}
