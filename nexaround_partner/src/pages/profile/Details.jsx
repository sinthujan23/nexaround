import { useOutletContext } from 'react-router-dom';
import { CompassIcon, ImageIcon } from '../../components/Icons';
import { Section } from '../../components/Kit';
import { TextArea, TextField } from '../../components/Forms';
import ImageUploader from '../../components/ImageUploader';

export default function ProfileDetails() {
  const { form, patch, setPhotosBusy } = useOutletContext();
  return (
    <div>
      <Section tone="teal" icon={CompassIcon} title="Business details" hint="Your name and what you offer.">
        <TextField
          label="Business name" required value={form.name}
          onChange={(v) => patch({ name: v })}
        />
        <TextArea
          label="Description" rows={5} value={form.description}
          placeholder="What you offer and what makes it worth booking"
          onChange={(v) => patch({ description: v })}
        />
      </Section>
      <Section tone="violet" icon={ImageIcon} title="Photos" hint="Photos of your business. The first is the main one.">
        <ImageUploader
          label={null}
          value={form.photo_urls || []}
          uploadEndpoint="/partner/upload"
          onUploadingChange={setPhotosBusy}
          onChange={(urls) => patch({ photo_urls: urls })}
        />
      </Section>
    </div>
  );
}
