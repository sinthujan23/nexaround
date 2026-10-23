import {
  Navigate, Outlet, Route, RouterProvider, createBrowserRouter, createRoutesFromElements,
} from 'react-router-dom';
import { AuthProvider, RequireAuth } from './auth';
import { ConfirmProvider } from './confirm';
import { ToastProvider } from './toast';
import AppShell from './components/AppShell';
import { AgreementGate, AgreementPage } from './components/Agreement';
import Login from './pages/Login';
import ForgotPassword from './pages/ForgotPassword';
import SetPassword from './pages/SetPassword';
import Dashboard from './pages/Dashboard';
import Packages from './pages/Packages';
import PackageEditor from './pages/PackageEditor';
import Reviews from './pages/Reviews';
import Requests from './pages/Requests';
import ProfileLayout from './pages/profile/Layout';
import ProfileDetails from './pages/profile/Details';
import ProfileLocation from './pages/profile/Location';
import ProfileContact from './pages/profile/Contact';
import SecurityLayout from './pages/security/Layout';
import Devices from './pages/security/Devices';
import Activity from './pages/security/Activity';

/** Everything below the router can use the vendor, the toast and the confirm dialog. */
function Providers() {
  return (
    <AuthProvider>
      <ToastProvider>
        <ConfirmProvider>
          <Outlet />
        </ConfirmProvider>
      </ToastProvider>
    </AuthProvider>
  );
}

/**
 * One URL per page. A data router (not <BrowserRouter>) because the forms use
 * `useBlocker` to stop a vendor leaving with unsaved edits.
 *
 * /login, /forgot-password and /set-password sit outside the sign-in gate:
 * the invite link is the first URL any vendor ever opens, and they have no
 * token when they open it.
 */
const router = createBrowserRouter(createRoutesFromElements(
  <Route element={<Providers />}>
    <Route path="/login" element={<Login />} />
    <Route path="/forgot-password" element={<ForgotPassword />} />
    <Route path="/set-password" element={<SetPassword />} />

    {/* The gate shows the Provider Agreement, full page, until it is accepted. */}
    <Route element={<RequireAuth><AgreementGate><AppShell /></AgreementGate></RequireAuth>}>
      <Route path="/dashboard" element={<Dashboard />} />

      <Route path="/packages" element={<Packages />} />
      <Route path="/packages/new" element={<PackageEditor />} />
      <Route path="/packages/:packageId" element={<PackageEditor />} />

      <Route path="/reviews" element={<Reviews />} />
      <Route path="/requests" element={<Requests />} />
      <Route path="/requests/:requestId" element={<Requests />} />

      <Route path="/profile" element={<ProfileLayout />}>
        <Route index element={<Navigate to="details" replace />} />
        <Route path="details" element={<ProfileDetails />} />
        <Route path="location" element={<ProfileLocation />} />
        <Route path="contact" element={<ProfileContact />} />
      </Route>

      <Route path="/agreement" element={<AgreementPage />} />

      <Route path="/security" element={<SecurityLayout />}>
        <Route index element={<Devices />} />
        <Route path="activity" element={<Activity />} />
      </Route>
    </Route>

    <Route path="*" element={<Navigate to="/dashboard" replace />} />
  </Route>
));

export default function App() {
  return <RouterProvider router={router} />;
}
