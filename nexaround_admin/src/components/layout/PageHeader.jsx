export default function PageHeader({ title }) {
  return (
    <header className="page-header">
      <div>
        <div className="page-title">{title}</div>
      </div>
    </header>
  );
}
