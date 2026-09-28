// Sagroeurope — Transfers hub: local, international transfers + crypto withdrawals
(async function () {
  await AppShell.init({ title: 'Transfers' });
  const user = Auth.user;

  function renderLocal(rows) {
    const el = document.getElementById('local-table');
    if (!rows.length) { el.innerHTML = UI.emptyState('No local transfers yet'); return; }
    el.innerHTML = '<table class="table mobile-cards"><thead><tr><th>Reference</th><th>Recipient</th><th>Amount</th><th>Status</th><th>Date</th></tr></thead><tbody>' +
      rows.map(function (t) {
        const isFailed = t.status === 'failed' || t.status === 'on_hold' || t.status === 'cancelled' || t.status === 'rejected';
        return '<tr class="' + (isFailed ? 'failed-row' : '') + '"><td data-label="Reference">' + UI.escapeHtml(t.reference) + '</td>' +
          '<td data-label="Recipient">' + UI.escapeHtml(t.recipient_name) + '</td>' +
          '<td data-label="Amount">' + UI.money(t.amount, t.currency) + '</td>' +
          '<td data-label="Status">' + UI.badge(t.status) + (isFailed ? ' <span class="text-danger text-sm">Transaction Failed</span>' : '') + '</td>' +
          '<td data-label="Date">' + UI.formatDateTime(t.created_at) + '</td></tr>';
      }).join('') + '</tbody></table>';
  }

  function renderIntl(rows) {
    const el = document.getElementById('intl-table');
    if (!rows.length) { el.innerHTML = UI.emptyState('No international transfers yet'); return; }
    el.innerHTML = '<table class="table mobile-cards"><thead><tr><th>Reference</th><th>Recipient</th><th>Country</th><th>Amount</th><th>Status</th><th>Date</th></tr></thead><tbody>' +
      rows.map(function (t) {
        const isFailed = t.status === 'failed' || t.status === 'on_hold' || t.status === 'cancelled' || t.status === 'rejected';
        return '<tr class="' + (isFailed ? 'failed-row' : '') + '"><td data-label="Reference">' + UI.escapeHtml(t.reference) + '</td>' +
          '<td data-label="Recipient">' + UI.escapeHtml(t.recipient_name) + '</td>' +
          '<td data-label="Country">' + UI.escapeHtml(t.recipient_country) + '</td>' +
          '<td data-label="Amount">' + UI.money(t.amount, t.currency) + '</td>' +
          '<td data-label="Status">' + UI.badge(t.status) + (isFailed ? ' <span class="text-danger text-sm">Transaction Failed</span>' : '') + '</td>' +
          '<td data-label="Date">' + UI.formatDateTime(t.created_at) + '</td></tr>';
      }).join('') + '</tbody></table>';
  }

  function renderCrypto(rows) {
    const el = document.getElementById('crypto-table');
    if (!rows.length) { el.innerHTML = UI.emptyState('No crypto withdrawals yet'); return; }
    el.innerHTML = '<table class="table mobile-cards"><thead><tr><th>Reference</th><th>Asset</th><th>Network</th><th>Amount</th><th>Debited</th><th>Status</th><th>Date</th></tr></thead><tbody>' +
      rows.map(function (t) {
        const isFailed = t.status === 'failed' || t.status === 'on_hold' || t.status === 'cancelled' || t.status === 'rejected';
        return '<tr class="' + (isFailed ? 'failed-row' : '') + '"><td data-label="Reference">' + UI.escapeHtml(t.reference) + '</td>' +
          '<td data-label="Asset">' + UI.escapeHtml(t.asset) + '</td>' +
          '<td data-label="Network">' + UI.escapeHtml(t.network) + '</td>' +
          '<td data-label="Amount">' + UI.money(t.amount, t.asset) + '</td>' +
          '<td data-label="Debited">' + UI.money(t.amount_fiat, t.currency) + (t.fee ? ' + ' + UI.money(t.fee, t.currency) + ' fee' : '') + '</td>' +
          '<td data-label="Status">' + UI.badge(t.status) + (isFailed ? ' <span class="text-danger text-sm">Transaction Failed</span>' : '') + '</td>' +
          '<td data-label="Date">' + UI.formatDateTime(t.created_at) + '</td></tr>';
      }).join('') + '</tbody></table>';
  }

  async function load() {
    try {
      const profile = await Auth.fetchProfile();
      const banner = document.getElementById('outgoing-banner');
      if (profile.outgoing_transfers_enabled === false) {
        banner.classList.remove('hide');
        document.getElementById('outgoing-banner-reason').textContent =
          (profile.outgoing_transfers_disabled_reason ? 'Reason: ' + profile.outgoing_transfers_disabled_reason : 'Please contact support for details.');
      } else {
        banner.classList.add('hide');
      }

      const [local, intl, crypto] = await Promise.all([
        SB.from('local_transfers').select('*').eq('user_id', user.id).order('created_at', { ascending: false }).limit(50),
        SB.from('international_transfers').select('*').eq('user_id', user.id).order('created_at', { ascending: false }).limit(50),
        SB.from('crypto_withdrawals').select('*').eq('user_id', user.id).order('created_at', { ascending: false }).limit(50)
      ]);
      if (local.error) throw local.error;
      if (intl.error) throw intl.error;
      if (crypto.error) throw crypto.error;
      renderLocal(local.data || []);
      renderIntl(intl.data || []);
      renderCrypto(crypto.data || []);
    } catch (e) {
      UI.toast(UI.apiErrorMessage(e), 'error');
    }
  }

  await load();
  PageLoader.hide();
})();