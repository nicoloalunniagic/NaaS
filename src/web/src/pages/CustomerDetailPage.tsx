import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
	api,
	type Customer,
	type Project,
	type ProjectInput,
	VAPT_LAB_MODE
} from '../api'

export default function CustomerDetailPage() {
	const { id } = useParams()
	const customerId = Number(id)
	const [customer, setCustomer] = useState<Customer | null>(null)
	const [projects, setProjects] = useState<Project[]>([])
	const [form, setForm] = useState<ProjectInput>({
		name: '',
		description: '',
		customerId
	})
	const [error, setError] = useState<string | null>(null)
	// XSS demo: local notes field rendered safely or unsafely depending on VAPT_LAB_MODE
	const [notes, setNotes] = useState('')

	async function reload() {
		try {
			setCustomer(await api.customers.get(customerId))
			setProjects(await api.customers.projects(customerId))
		} catch (e) {
			setError((e as Error).message)
		}
	}

	useEffect(() => {
		setForm({ name: '', description: '', customerId })
		void reload()
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [customerId])

	async function addProject(e: React.FormEvent) {
		e.preventDefault()
		setError(null)
		try {
			await api.projects.create(form)
			setForm({ name: '', description: '', customerId })
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	async function removeProject(pid: number) {
		if (!confirm('Delete this project?')) return
		try {
			await api.projects.remove(pid)
			await reload()
		} catch (err) {
			setError((err as Error).message)
		}
	}

	if (!customer) {
		return (
			<>
				<p>
					<Link to='/customers'>← Back to customers</Link>
				</p>
				{error ? <div className='error'>{error}</div> : <p>Loading…</p>}
			</>
		)
	}

	return (
		<>
			<p>
				<Link to='/customers'>← Back to customers</Link>
			</p>
			<h1>{customer.name}</h1>
			<p className='muted'>
				ID #{customer.id} · CF {customer.codiceFiscale} ·{' '}
				{customer.email ?? 'no email'} · created{' '}
				{new Date(customer.createdAt).toLocaleString()}
			</p>

			{error && <div className='error'>{error}</div>}
			{/* ── VAPT Lab: XSS demo ─────────────────────────────────────────
		    INTENTIONAL VAPT LAB VULNERABILITY (when VAPT_LAB_MODE=true):
		      Notes are rendered via dangerouslySetInnerHTML — any HTML/JS the
		      user types (e.g. <img src=x onerror=alert(1)>) is executed.
		    Safe behaviour: notes are rendered as plain escaped text.
		    ────────────────────────────────────────────────────────────── */}
			<h2>Customer Notes</h2>
			<label style={{ display: 'block', marginBottom: '4px', fontWeight: 500 }}>
				{VAPT_LAB_MODE
					? '⚠ VAPT LAB: Notes rendered as raw HTML (XSS vulnerable)'
					: 'Notes (rendered as plain text)'}
			</label>
			<textarea
				rows={3}
				style={{ width: '100%', marginBottom: '8px', fontFamily: 'monospace' }}
				value={notes}
				onChange={e => setNotes(e.target.value)}
				placeholder={
					VAPT_LAB_MODE
						? 'Try: <img src=x onerror=alert(document.cookie)>'
						: 'Type any notes about this customer'
				}
			/>
			{VAPT_LAB_MODE ? (
				/* INTENTIONAL VAPT LAB VULNERABILITY: XSS */
				<div
					style={{
						border: '2px solid #b91c1c',
						padding: '8px',
						minHeight: '2rem'
					}}
					dangerouslySetInnerHTML={{ __html: notes }}
				/>
			) : (
				/* Safe: React escapes the string automatically */
				<div
					style={{
						border: '1px solid #ccc',
						padding: '8px',
						minHeight: '2rem'
					}}
				>
					{notes}
				</div>
			)}
			{/* ───────────────────────────────────────────────────────────── */}
			<h2>Projects</h2>
			<table>
				<thead>
					<tr>
						<th>ID</th>
						<th>Name</th>
						<th>Description</th>
						<th>Created</th>
						<th></th>
					</tr>
				</thead>
				<tbody>
					{projects.map(p => (
						<tr key={p.id}>
							<td>{p.id}</td>
							<td>{p.name}</td>
							<td>{p.description ?? '—'}</td>
							<td>{new Date(p.createdAt).toLocaleString()}</td>
							<td>
								<button className='danger' onClick={() => removeProject(p.id)}>
									Delete
								</button>
							</td>
						</tr>
					))}
					{projects.length === 0 && (
						<tr>
							<td colSpan={5} className='muted'>
								No projects for this customer.
							</td>
						</tr>
					)}
				</tbody>
			</table>

			<h3>New project</h3>
			<form className='stack' onSubmit={addProject}>
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
						Create project
					</button>
				</div>
			</form>
		</>
	)
}
