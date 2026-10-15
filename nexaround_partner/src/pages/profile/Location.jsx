import { useOutletContext } from 'react-router-dom';
import { MapPinIcon } from '../../components/Icons';
import { Section } from '../../components/Kit';
import { FieldGrid, TextField, SelectField } from '../../components/Forms';
import LocationPicker from '../../components/LocationPicker';
import { COUNTRIES, normalizeCountryCode } from '../../constants/countries';

const COUNTRY_OPTIONS = [{ value: '', label: 'Choose a country' }].concat(COUNTRIES.map((c) => ({ value: c.code, label: `${c.flag} ${c.name} (${c.code})` })));

export default function ProfileLocation() {
  const { form, patch } = useOutletContext();
  return (
    <Section tone="rose" icon={MapPinIcon} title="Location" hint="Where travellers find you. The map pin is optional; the country is required.">
      <FieldGrid cols={2}>
        <TextField label="City" placeholder="Trincomalee" value={form.city} onChange={(v) => patch({ city: v })} />
        <SelectField
          label="Country *" options={COUNTRY_OPTIONS}
          value={form.country_code ? normalizeCountryCode(form.country_code) : ''}
          onChange={(v) => patch({ country_code: v })}
        />
      </FieldGrid>
      <LocationPicker
        optional
        mapId="partner-location-map"
        latitude={form.latitude ?? ''}
        longitude={form.longitude ?? ''}
        address={form.address || ''}
        searchEndpoint="/partner/place-search"
        onPick={(p) => {
          // The picker also offers a name and a Google place id. The name is
          // the vendor's to choose, and the place id is admin-only, so both
          // are dropped here rather than relied on being ignored downstream.
          const next = { ...p };
          // A place with no country of its own must not wipe the one chosen.
          if ('country_code' in next && !next.country_code) delete next.country_code;
          delete next.name;
          delete next.google_place_id;
          if (next.country_code) {
            next.country_code = normalizeCountryCode(next.country_code);
          }
          patch(next);
        }}
      />
    </Section>
  );
}
