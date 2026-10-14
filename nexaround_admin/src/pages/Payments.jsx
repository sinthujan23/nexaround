import { CreditCardIcon } from '../components/Icons';
import { EmptyState } from '../components/Kit';

export default function Payments() {
  return (
    <div className="card">
      <EmptyState icon={<CreditCardIcon size={28} />} title="Payments & plans are coming soon">
        Subscription management, payment gateways, and billing transactions will appear here once enabled.
      </EmptyState>
    </div>
  );
}
