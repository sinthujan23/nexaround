import { useOutletContext } from 'react-router-dom';
import { PhoneIcon, GlobeIcon } from '../../components/Icons';
import { Section } from '../../components/Kit';
import { FieldGrid, TextField } from '../../components/Forms';

// Phone, WhatsApp and the social links are how travellers reach the vendor, so
// only NexAround sets them; the server ignores them from here.
const MANAGED = 'Managed by NexAround';

export default function ProfileContact() {
  const { form, patch } = useOutletContext();
  return (
    <div>
      <Section tone="green" icon={PhoneIcon} title="Direct contact" hint="Your email is not shown in the app. To change your phone or WhatsApp, contact NexAround.">
        <FieldGrid cols={2}>
          <TextField label="Phone" placeholder={MANAGED} value={form.contact_phone} onChange={() => {}} disabled />
          <TextField label="WhatsApp" placeholder={MANAGED} value={form.contact_whatsapp} onChange={() => {}} disabled />
          <TextField label="Email" type="email" placeholder="bookings@business.com" value={form.contact_email} onChange={(v) => patch({ contact_email: v })} />
          <TextField label="Website" placeholder="https://business.com" value={form.website} onChange={(v) => patch({ website: v })} />
        </FieldGrid>
      </Section>
      <Section tone="blue" icon={GlobeIcon} title="Social" hint="Managed by NexAround. To change a link, contact NexAround.">
        <FieldGrid cols={3}>
          <TextField label="Instagram" placeholder={MANAGED} value={form.contact_instagram} onChange={() => {}} disabled />
          <TextField label="Facebook" placeholder={MANAGED} value={form.contact_facebook} onChange={() => {}} disabled />
          <TextField label="X" placeholder={MANAGED} value={form.contact_x} onChange={() => {}} disabled />
        </FieldGrid>
      </Section>
    </div>
  );
}
