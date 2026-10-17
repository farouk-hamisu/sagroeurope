// Sagroeurope — Admin Deposits module
(async function () {
  const admin = await AdminAuth.requireAuth();
  if (!admin) return;
  renderAdminShell('Deposits');

  const PAGE = 12;
  let page = 1;
  let type = 'all'; // 'all', 'fiat', 'crypto'
  const STATUSES = ['pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'];

  document.getElementById('f-status').innerHTML = '<option value="">All statuses</option>' + 
    ['pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'].map(function (s) { 
      return '<option value="' + s + '">' + UI.typeLabel(s) + '</option>'; 
    }).join('');

  async function load() {
    const el = document.getElementById('deposit-table');
    el.innerHTML = '<div class="loading-block"><div class="spinner"></div><span>Loading deposits...</span></div>';
    try {
      const search = document.getElementById('f-search').value.trim();
      const status = document.getElementById('f-status').value || null;
      const typeFilter = document.getElementById('f-type').value;
      const assetFilter = document.getElementById('f-asset').value;
      
      const fn = 'admin_list_deposits';
      const res = await adminApi(fn, { 
        p_search: search, 
        p_status: status, 
        p_type: typeFilter || null,
        p_asset: assetFilter || null,
        p_limit: PAGE, 
        p_offset: (page - 1) * PAGE 
      });
      render(res.rows || []);
      renderPagination(res.total || 0);
    } catch (e) {
      el.innerHTML = UI.emptyState('Could not load deposits');
      UI.toast(UI.apiErrorMessage(e), 'error');
    }
  }

  function render(rows) {
    const el = document.getElementById('deposit-table');
    if (!rows.length) { el.innerHTML = UI.emptyState('No deposits found'); return; }
    
    el.innerHTML = '<table class="table mobile-cards">' +
      '<thead><tr><th>Reference</th><th>User</th><th>Type</th><th>Asset</th><th>Amount</th><th>Status</th><th>Date</th><th>Actions</th></tr></thead><tbody>' +
      rows.map(function (t) {
        const isCrypto = t.type === 'crypto';
        const isPending = t.status === 'pending' || t.status === 'pending_verification';
        const isFailed = t.status === 'failed' || t.status === 'cancelled' || t.status === 'rejected';
        
        return '<tr class="' + (isFailed ? 'failed-row' : '') + '"><td data-label="Reference"><span class="cell-main">' + UI.escapeHtml(t.reference) + '</span></td>' +
          '<td data-label="User">' + UI.escapeHtml(t.user_email || '') + '<div class="cell-sub">' + UI.escapeHtml(t.user_name || '') + '</div></td>' +
          '<td data-label="Type"><span class="badge ' + (t.type === 'crypto' ? 'badge-info' : 'badge-success') + '">' + UI.typeLabel(t.type || 'fiat') + '</span></td>' +
          '<td data-label="Asset">' + UI.escapeHtml(t.asset || t.currency || '') + '</td>' +
          '<td data-label="Amount">' + UI.money(t.amount || t.amount_fiat, t.currency) + (t.amount_crypto ? ' (' + t.amount_crypto + ' ' + t.asset + ')' : '') + '</td>' +
          '<td data-label="Status">' + UI.badge(t.status) + (t.status === 'pending_verification' ? ' <span class="text-warning text-sm">Awaiting Verification</span>' : '') + '</td>' +
          '<td data-label="Date">' + UI.formatDateTime(t.created_at) + '</td>' +
          '<td data-label="Actions"><div class="row-actions">' +
            '<button class="row-action" data-view="' + t.id + '" title="View">' + ICONS.eye + '</button>' +
            (isPending ? '<button class="row-action" data-verify="' + t.id + '" title="Verify Deposit" style="color:var(--primary)">' + ICONS.shield + '</button>' : '') +
            '<button class="row-action" data-status="' + t.id + '" title="Update status">' + ICONS.edit + '</button>' +
          '</div></td></tr>';
      }).join('') + '</tbody></table>';

    // Event listeners for actions
    el.querySelectorAll('[data-view]').forEach(function (b) {
      b.addEventListener('click', function () {
        const t = rows.find(function (x) { return x.id === b.getAttribute('data-view'); });
        showDepositDetail(t);
      });
    });

    el.querySelectorAll('[data-verify]').forEach(function (b) {
      b.addEventListener('click', function () {
        const t = rows.find(function (x) { return x.id === b.getAttribute('data-verify'); });
        verifyDeposit(t);
      });
    });

    el.querySelectorAll('[data-status]').forEach(function (b) {
      b.addEventListener('click', function () {
        const t = rows.find(function (x) { return x.id === b.getAttribute('data-status'); });
        updateStatus(t);
      });
    });
  }

  function showDepositDetail(t) {
    const fields = [
      ['Reference', t.reference], ['User', t.user_name + ' (' + t.user_email + ')'],
      ['Type', UI.typeLabel(t.type || 'fiat')], ['Asset', t.asset || t.currency || '—'],
      ['Network', t.network || '—'], ['Amount', UI.money(t.amount || t.amount_fiat, t.currency)],
      t.amount_crypto ? ['Crypto Amount', t.amount_crypto + ' ' + t.asset] : null,
      ['Fee', UI.money(t.fee || 0, t.currency)], ['Status', UI.badge(t.status)],
      ['Reference', t.reference], ['Network', t.network || '—'],
      t.address ? ['Address', t.address] : null,
      t.tx_hash ? ['Tx Hash', t.tx_hash] : null,
      t.proof_image_url ? ['Proof Image', '<a href="' + t.proof_image_url + '" target="_blank">View Proof</a>'] : null,
      ['Description', t.description || '—'], ['Created', UI.formatDateTime(t.created_at)],
      t.verified_at ? ['Verified At', UI.formatDateTime(t.verified_at)] : null,
      t.verified_by ? ['Verified By', t.verified_by_name || t.verified_by] : null
    ].filter(Boolean).map(function (f) {
      return '<div class="detail-item"><div class="k">' + f[0] + '</div><div class="v">' + f[1] + '</div></div>';
    }).join('');

    UI.openModal('<div class="detail-grid">' + fields + '</div>', { title: 'Deposit Details' });
  }

  async function verifyDeposit(t) {
    if (!confirm('Approve this deposit and credit the user\'s account?')) return;
    
    try {
      await adminApi('admin_verify_crypto_deposit', { 
        p_deposit_id: t.id, 
        p_action: 'approve' 
      });
      UI.toast('Deposit approved and credited.', 'success');
      load();
    } catch (e) {
      UI.toast(UI.apiErrorMessage(e), 'error');
    }
  }

  function updateStatus(t) {
    const modal = UI.openModal(
      '<div class="field"><label>New status</label><select class="select" id="st-status">' +
        ['pending', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'].map(function (s) { 
          return '<option value="' + s + '"' + (s === t.status ? ' selected' : '') + '>' + UI.typeLabel(s) + '</option>'; 
        }).join('') +
      '</select></div><div class="form-error" id="st-error"></div>',
      { title: 'Update Status — ' + t.reference, footer: '<button class="btn btn-outline" data-cancel>Cancel</button><button class="btn btn-primary" data-save>Update</button>' }
    );
    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);
    modal.footer.querySelector('[data-save]').addEventListener('click', async function () {
      try {
        await adminApi('admin_update_deposit_status', { p_deposit_id: t.id, p_status: document.getElementById('st-status').value });
        UI.toast('Deposit status updated.', 'success');
        modal.close();
        load();
      } catch (e) { document.getElementById('st-error').textContent = UI.apiErrorMessage(e); }
    });
  }

  function renderPagination(total) {
    const pages = Math.max(1, Math.ceil(total / PAGE));
    const el = document.getElementById('pagination');
    let html = '<button data-p="' + (page - 1) + '" ' + (page <= 1 ? 'disabled' : '') + '>‹</button>';
    for (let i = 1; i <= pages; i++) html += '<button data-p="' + i + '" class="' + (i === page ? 'active' : '') + '">' + i + '</button>';
    html += '<button data-p="' + (page + 1) + '" ' + (page >= pages ? 'disabled' : '') + '>›</button>';
    el.innerHTML = html;
    el.querySelectorAll('button[data-p]').forEach(function (b) {
      b.addEventListener('click', function () { page = Number(b.getAttribute('data-p')); load(); });
    });
  }

  document.getElementById('f-search').addEventListener('input', function () { page = 1; load(); });
  document.getElementById('f-status').addEventListener('change', function () { page = 1; load(); });
  document.getElementById('f-type').addEventListener('change', function () { page = 1; load(); });
  document.getElementById('f-asset').addEventListener('change', function () { page = 1; load(); });

  // Initialize asset filter
  async function initAssetFilter() {
    try {
      const { data } = await SB.from('crypto_assets').select('asset').distinct();
      const select = document.getElementById('f-asset');
      select.innerHTML = '<option value="">All assets</option>' + (data || []).map(function (a) {
        return '<option value="' + a.asset + '">' + a.asset + '</option>';
      }).join('');
    } catch (e) {
      console.error('Failed to load assets:', e);
    }
  }

  await initAssetFilter();
  await load();
  PageLoader.hide();
})();
EOF
echo "Created: js/admin/deposits.js"