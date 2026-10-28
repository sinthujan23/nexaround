// Who is signed in, read from the token itself. Two kinds of people use this
// panel: admins, and City Tours content creators (role "creator"), whose
// panel shows City Tours only. The server decides what each may do; this only
// picks what the panel shows, so a hand-edited token gains nothing.

function claims() {
  const token = localStorage.getItem('admin_token');
  if (!token) return {};
  try {
    const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const json = decodeURIComponent(
      atob(part).split('').map((c) => `%${c.charCodeAt(0).toString(16).padStart(2, '0')}`).join(''),
    );
    return JSON.parse(json) || {};
  } catch {
    return {};
  }
}

export const ADMIN = 'admin';
export const CREATOR = 'creator';

export const sessionRole = () => (claims().role === CREATOR ? CREATOR : ADMIN);

export const isCreator = () => sessionRole() === CREATOR;

/** The creator's name, as the admin typed it; "Admin" for the admin. */
export const sessionName = () => (isCreator() ? claims().name || 'Creator' : 'Admin');
