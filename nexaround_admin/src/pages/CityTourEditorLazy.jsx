import { lazy, Suspense } from 'react';
import { PageLoading } from '../components/Kit';

// The guide editor carries the Word-style editor (TipTap), as big as the rest
// of the panel together; it is fetched when the editor is first opened, not
// on every visit to the panel.
const CityTourEditorPage = lazy(() => import('./CityTourEditor'));

export default function CityTourEditor() {
  return (
    <Suspense fallback={<PageLoading />}>
      <CityTourEditorPage />
    </Suspense>
  );
}
