import { useAuth } from '../auth/AuthContext'

export function SupervisorDashboard() {
  return <><h1 className="text-3xl font-bold">Supervisor dashboard</h1><p className="mt-2 text-slate-600">Manage the staff directory and roster configuration.</p><div className="mt-6 grid gap-4 sm:grid-cols-3">{['Staff', 'Locations', 'Activity types'].map((item) => <div className="card" key={item}><h2 className="font-semibold">{item}</h2><p className="mt-1 text-sm text-slate-600">Foundation configuration is ready.</p></div>)}</div></>
}

export function EmployeeDashboard() {
  return <><h1 className="text-3xl font-bold">Employee dashboard</h1><p className="mt-2 text-slate-600">Welcome. Availability and schedule features arrive in later milestones.</p><div className="card mt-6"><h2 className="font-semibold">No actions yet</h2><p className="mt-1 text-slate-600">Your account and profile are ready.</p></div></>
}

export function ProfilePage() {
  const { profile } = useAuth()
  return <><h1 className="text-3xl font-bold">Profile</h1><dl className="card mt-6 grid gap-4 sm:grid-cols-2"><div><dt className="text-sm text-slate-500">Name</dt><dd className="font-medium">{profile?.full_name}</dd></div><div><dt className="text-sm text-slate-500">Email</dt><dd className="font-medium">{profile?.email}</dd></div><div><dt className="text-sm text-slate-500">Role</dt><dd className="font-medium capitalize">{profile?.role}</dd></div><div><dt className="text-sm text-slate-500">Timezone</dt><dd className="font-medium">Australia/Melbourne</dd></div></dl></>
}

export function UnauthorisedPage() {
  return <div className="card" role="alert"><h1 className="text-2xl font-bold">Unauthorised</h1><p className="mt-2 text-slate-600">Your role does not permit access to that page.</p></div>
}
