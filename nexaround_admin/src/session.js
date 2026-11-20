// Who is signed in, read from the token itself. Two kinds of people use this
// panel: admins, and team members (role "creator", the name from when members
// only wrote City Tours), whose panel shows only the areas the admin gave them.
// The server decides what each may do; this only picks what the panel shows,
// so a hand-edited token gains nothing.

function claims(token = localStorage.getItem('admin_token')) {
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
export const CREATOR = 'creator'; // a team member

// Areas a team member can be given (the server's creator_auth.SECTIONS).
export const CITY_TOURS = 'city_tours';
export const EXPERIENCES = 'experiences';
export const TRAVEL_BYTES = 'travel_bytes';
export const MUSEUMS = 'museums';

/** Whether this token's expiry time (`exp`, in seconds) has passed. A token
 * with no readable expiry counts as not expired: the server decides then. */
export const tokenExpired = (token) => {
  const { exp } = claims(token);
  return typeof exp === 'number' && exp * 1000 <= Date.now();
};

export const sessionRole = () => (claims().role === CREATOR ? CREATOR : ADMIN);

export const isCreator = () => sessionRole() === CREATOR;

/** The areas a team member may open. A token from before areas existed was
 * a City Tours writer's. Empty for the admin, who is not limited by them. */
export const sessionSections = () => {
  if (!isCreator()) return [];
  const { sections } = claims();
  return Array.isArray(sections) ? sections : [CITY_TOURS];
};

/** Whether this login puts City Guides live itself: the admin, and members
 * the admin allowed to. Other members send each guide for review. */
export const canPublishGuides = () => !isCreator() || claims().publish === true;

/** The member's name, as the admin typed it; "Admin" for the admin. */
export const sessionName = () => (isCreator() ? claims().name || 'Team member' : 'Admin');
