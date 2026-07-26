import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { AuthProvider } from './auth/AuthContext'
import { RequireAuth, RequireRole, RoleHome } from './auth/RouteGuards'
import { AppShell } from './components/AppShell'
import { EmployeeDashboard, ProfilePage, SupervisorDashboard, UnauthorisedPage } from './pages/DashboardPages'
import { ReferenceManagementPage } from './pages/ReferenceManagementPage'
import { SignInPage } from './pages/SignInPage'
import { StaffManagementPage } from './pages/StaffManagementPage'
import { EmployeeAvailabilityPage, SupervisorAvailabilityPage } from './pages/AvailabilityPages'
import { RosterPage } from './pages/RosterPage'

export function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/sign-in" element={<SignInPage />} />
          <Route element={<RequireAuth />}>
            <Route element={<AppShell />}>
              <Route index element={<RoleHome />} />
              <Route path="profile" element={<ProfilePage />} />
              <Route path="unauthorised" element={<UnauthorisedPage />} />
              <Route element={<RequireRole role="employee" />}>
                <Route path="employee" element={<EmployeeDashboard />} />
                <Route path="employee/availability" element={<EmployeeAvailabilityPage />} />
              </Route>
              <Route element={<RequireRole role="supervisor" />}>
                <Route path="supervisor" element={<SupervisorDashboard />} />
                <Route path="supervisor/staff" element={<StaffManagementPage />} />
                <Route path="supervisor/availability" element={<SupervisorAvailabilityPage />} />
                <Route path="supervisor/roster" element={<RosterPage />} />
                <Route path="supervisor/locations" element={<ReferenceManagementPage table="locations" title="Locations" />} />
                <Route path="supervisor/activity-types" element={<ReferenceManagementPage table="activity_types" title="Activity types" />} />
              </Route>
            </Route>
          </Route>
          <Route path="*" element={<RoleHome />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}
