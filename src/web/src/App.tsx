import { NavLink, Route, Routes, Navigate } from 'react-router-dom'
import CustomersPage from './pages/CustomersPage'
import CustomerDetailPage from './pages/CustomerDetailPage'
import ProjectsPage from './pages/ProjectsPage'

export default function App() {
	return (
		<>
			<nav className='top'>
				<strong>NaaS Admin</strong>
				<NavLink to='/customers'>Customers</NavLink>
				<NavLink to='/projects'>Projects</NavLink>
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
