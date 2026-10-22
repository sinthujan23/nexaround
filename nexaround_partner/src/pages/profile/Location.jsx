import { useOutletContext } from 'react-router-dom';
import { MapPinIcon } from '../../components/Icons';
import { Section } from '../../components/Kit';
import { FieldGrid, TextField } from '../../components/Forms';
import { getCountryByCode } from '../../constants/countries';

// Where the business is, shown read-only: only NexAround sets it, so
// travellers meet and book the business through NexAround.
const MANAGED = 'Set by NexAround';

export default function ProfileLocation() {
  const { form } = useOutletContext();
  const country = form.country_code ? getCountryByCode(form.country_code) : null;
  return (
    <Section
      tone="rose" icon={MapPinIcon} title="Location"
      hint="Set by NexAround. To change where your business is, contact NexAround."
    >
      <FieldGrid cols={2}>
        <TextField label="City" placeholder={MANAGED} value={form.city} onChange={() => {}} disabled />
        <TextField
          label="Country" placeholder={MANAGED}
          value={country ? `${country.flag} ${country.name}` : ''} onChange={() => {}} disabled
        />
      </FieldGrid>
      <TextField label="Address" placeholder={MANAGED} value={form.address} onChange={() => {}} disabled />
    </Section>
  );
}
