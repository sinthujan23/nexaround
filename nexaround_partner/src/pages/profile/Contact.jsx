import { useOutletContext } from 'react-router-dom';
import { PhoneIcon, GlobeIcon } from '../../components/Icons';
import { Section } from '../../components/Kit';
import { FieldGrid, TextField } from '../../components/Forms';

export default function ProfileContact() {
  const { form, patch } = useOutletContext();
  return (
    <div>
      <Section tone="green" icon={PhoneIcon} title="Direct contact" hint="Your email receives new enquiries and is not shown in the app.">
        <FieldGrid cols={2}>
          <TextField label="Phone" placeholder="+94 77 123 4567" value={form.contact_phone} onChange={(v) => patch({ contact_phone: v })} />
          <TextField label="WhatsApp" placeholder="+94 77 123 4567" value={form.contact_whatsapp} onChange={(v) => patch({ contact_whatsapp: v })} />
          <TextField label="Email" type="email" placeholder="bookings@business.com" value={form.contact_email} onChange={(v) => patch({ contact_email: v })} />
          <TextField label="Website" placeholder="https://business.com" value={form.website} onChange={(v) => patch({ website: v })} />
        </FieldGrid>
      </Section>
      <Section tone="blue" icon={GlobeIcon} title="Social" hint="A handle or a full URL both work.">
        <FieldGrid cols={3}>
          <TextField label="Instagram" placeholder="@handle" value={form.contact_instagram} onChange={(v) => patch({ contact_instagram: v })} />
          <TextField label="Facebook" placeholder="facebook.com/…" value={form.contact_facebook} onChange={(v) => patch({ contact_facebook: v })} />
          <TextField label="X" placeholder="@handle" value={form.contact_x} onChange={(v) => patch({ contact_x: v })} />
        </FieldGrid>
      </Section>
    </div>
  );
}
