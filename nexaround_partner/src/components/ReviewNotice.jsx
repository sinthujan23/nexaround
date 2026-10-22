import { formatDateTime } from '../format';

/**
 * Where the vendor's own edits stand (services/vendor_review on the server):
 * NexAround checks content before travellers see it, while the live version
 * keeps showing. `item` is a package or the profile as the API returns it;
 * `isNew` for a package being added.
 */
export default function ReviewNotice({ item, isNew = false, what = 'package' }) {
  const status = item?.review_status;
  const firstTime = isNew || item?.is_approved === false;

  if (status === 'changes_requested') {
    return (
      <div className="review-notice tone-rose">
        <strong>NexAround asked for changes</strong>
        {item.review_note && <p className="review-note">{item.review_note}</p>}
        <span>Make the changes and save to send it for review again.</span>
      </div>
    );
  }
  if (status === 'pending') {
    return (
      <div className="review-notice tone-amber">
        <strong>Waiting for NexAround’s review</strong>
        <span>
          Sent {formatDateTime(item.submitted_at)}.{' '}
          {firstTime
            ? 'Travellers can see it once it is approved.'
            : `Travellers see the current ${what} until your changes are approved.`}
          {' '}You will get an email and an app notification when it is checked.
        </span>
      </div>
    );
  }
  return (
    <div className="review-notice tone-blue">
      <span>
        {firstTime
          ? 'New packages are checked by NexAround before travellers can see them.'
          : `Changes to the ${what}’s details, photos and prices are checked by NexAround before travellers see them.`}
        {what === 'package' && ' Availability and Show in the app apply straight away.'}
      </span>
    </div>
  );
}
