import { ImageIcon } from '../components/Icons';
import { EmptyState } from '../components/Kit';

// Not built yet. The page used to show three hard-coded sample items with
// buttons that only changed local state; admin pages show real data only, so
// it says plainly that the feature is on its way instead.
export default function Media() {
  return (
    <div className="card">
      <EmptyState icon={<ImageIcon size={28} />} title="Media library is coming soon">
        Photos people send from the app will appear here for review.
      </EmptyState>
    </div>
  );
}
