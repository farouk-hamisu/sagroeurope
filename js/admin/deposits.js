// Sagroeurope — Admin Deposits module
(async function () {
  const admin = await AdminAuth.requireAuth();
  if (!admin) return;
  renderAdminShell('Deposits');

  const PAGE = 12;
  let page = 1;
  const STATUSES = ['pending', 'processing', 'pending_verification', 'completed', 'failed', 'cancelled', 'rejected'];

  document.getElementById('f-status').innerHTML = '<option value="">All statuses</option>' +
    STATUSES.map(function (s) {
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

      const res = await adminApi('admin_list_deposits', {
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
        const amount = isCrypto
          ? Number(t.amount_crypto || t.amount || 0).toLocaleString('en-US', { maximumFractionDigits: 8 }) + ' ' + UI.escapeHtml(t.asset || '') +
            (t.amount_fiat != null ? ' <span class="cell-sub">(' + UI.money(t.amount_fiat, t.currency) + ')</span>' : '')
          : UI.money(t.amount || t.amount_fiat, t.currency);

        return '<tr class="' + (isFailed ? 'failed-row' : '') + '">' +
          '<td data-label="Reference"><span class="cell-main">' + UI.escapeHtml(t.reference) + '</span></td>' +
          '<td data-label="User">' + UI.escapeHtml(t.user_email || '') + '<div class="cell-sub">' + UI.escapeHtml(t.user_name || '') + '</div></td>' +
          '<td data-label="Type"><span class="badge ' + (isCrypto ? 'badge-info' : 'badge-success') + '">' + UI.typeLabel(t.type || 'fiat') + '</span></td>' +
          '<td data-label="Asset">' + UI.escapeHtml(t.asset || t.currency || '') + '</td>' +
          '<td data-label="Amount">' + amount + '</td>' +
          '<td data-label="Status">' + UI.badge(t.status) + (t.status === 'pending_verification' ? ' <span class="text-warning text-sm">Awaiting Verification</span>' : '') + '</td>' +
          '<td data-label="Date">' + UI.formatDateTime(t.created_at) + '</td>' +
          '<td data-label="Actions"><div class="row-actions">' +
            '<button class="row-action" data-view="' + t.id + '" title="View">' + ICONS.eye + '</button>' +
            (isPending ? '<button class="row-action" data-verify="' + t.id + '" title="Verify Deposit" style="color:var(--primary)">' + ICONS.shield + '</button>' : '') +
            (!isCrypto ? '<button class="row-action" data-status="' + t.id + '" title="Update status">' + ICONS.edit + '</button>' : '') +
          '</div></td></tr>';
      }).join('') + '</tbody></table>';

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

  function safeUrl(url) {
    const value = String(url || '').trim();
    return /^https?:\/\//i.test(value) ? value : '';
  }

  function showDepositDetail(t) {
    if (!t) return;
    const proofUrl = safeUrl(t.proof_image_url);
    const fields = [
      ['Reference', UI.escapeHtml(t.reference)],
      ['User', UI.escapeHtml((t.user_name || '') + ' (' + (t.user_email || '') + ')')],
      ['Type', UI.escapeHtml(UI.typeLabel(t.type || 'fiat'))],
      ['Asset', UI.escapeHtml(t.asset || t.currency || '—')],
      ['Network', UI.escapeHtml(t.network || '—')],
      ['Amount', t.type === 'crypto'
        ? UI.escapeHtml(Number(t.amount_crypto || t.amount || 0).toLocaleString('en-US', { maximumFractionDigits: 8 }) + ' ' + (t.asset || ''))
        : UI.money(t.amount || t.amount_fiat, t.currency)],
      t.type === 'crypto' && t.amount_fiat != null ? ['Fiat value', UI.money(t.amount_fiat, t.currency)] : null,
      ['Fee', UI.money(t.fee || 0, t.currency)],
      ['Status', UI.badge(t.status)],
      t.address ? ['Address', '<span class="tx-hash-line">' + UI.escapeHtml(t.address) + '</span>'] : null,
      t.tx_hash ? ['Tx Hash', '<span class="tx-hash-line">' + UI.escapeHtml(t.tx_hash) + '</span>'] : null,
      t.proof_image_url ? ['Proof Image', proofUrl
        ? '<a href="' + UI.escapeHtml(proofUrl) + '" target="_blank" rel="noopener noreferrer">View Proof</a>'
        : UI.escapeHtml(t.proof_image_url)] : null,
      ['Note', UI.escapeHtml(t.note || '—')],
      ['Created', UI.formatDateTime(t.created_at)],
      t.verified_at ? ['Verified At', UI.formatDateTime(t.verified_at)] : null,
      t.verified_by ? ['Verified By', UI.escapeHtml(t.verified_by_name || t.verified_by)] : null
    ].filter(Boolean).map(function (f) {
      return '<div class="detail-item"><div class="k">' + f[0] + '</div><div class="v">' + f[1] + '</div></div>';
    }).join('');

    UI.openModal('<div class="detail-grid">' + fields + '</div>', { title: 'Deposit Details' });
  }

  function verifyDeposit(t) {
    if (!t) return;
    if (t.type !== 'crypto') {
      UI.confirmDialog('Approve this deposit and credit the user\'s account?', async function () {
        try {
          await adminApi('admin_update_deposit_status', {
            p_deposit_id: t.id,
            p_status: 'completed'
          });
          UI.toast('Deposit approved.', 'success');
          load();
        } catch (e) {
          UI.toast(UI.apiErrorMessage(e), 'error');
        }
      }, 'Approve & Credit');
      return;
    }

    const modal = UI.openModal(
      '<div class="field"><label class="field-required" for="v-hash">Transaction hash</label>' +
        '<input class="input" id="v-hash" value="' + UI.escapeHtml(t.tx_hash || '') + '" placeholder="On-chain transaction hash" autocomplete="off">' +
        '<div class="hint">Required before the deposit can be credited.</div></div>' +
      '<div class="field"><label for="v-note">Admin note / rejection reason</label>' +
        '<textarea class="textarea" id="v-note" rows="3" placeholder="Optional for approval, required for rejection"></textarea></div>' +
      '<div class="form-error" id="v-error"></div>',
      {
        title: 'Verify Crypto Deposit — ' + t.reference,
        footer: '<button class="btn btn-outline" data-cancel>Cancel</button>' +
          '<button class="btn btn-danger" data-reject>Reject</button>' +
          '<button class="btn btn-primary" data-approve>Approve &amp; Credit</button>'
      }
    );
    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);

    modal.footer.querySelector('[data-approve]').addEventListener('click', async function () {
      const err = document.getElementById('v-error');
      const hash = document.getElementById('v-hash').value.trim();
      const note = document.getElementById('v-note').value.trim();
      err.textContent = '';
      if (!hash) { err.textContent = 'Transaction hash is required.'; return; }
      this.disabled = true;
      try {
        await adminApi('admin_verify_crypto_deposit', {
          p_deposit_id: t.id,
          p_action: 'approve',
          p_reason: note || null,
          p_tx_hash: hash
        });
        UI.toast('Crypto deposit approved and credited.', 'success');
        modal.close();
        load();
      } catch (e) {
        err.textContent = UI.apiErrorMessage(e);
        this.disabled = false;
      }
    });

    modal.footer.querySelector('[data-reject]').addEventListener('click', async function () {
      const err = document.getElementById('v-error');
      const note = document.getElementById('v-note').value.trim();
      err.textContent = '';
      if (!note) { err.textContent = 'Enter a rejection reason.'; return; }
      this.disabled = true;
      try {
        await adminApi('admin_verify_crypto_deposit', {
          p_deposit_id: t.id,
          p_action: 'reject',
          p_reason: note,
          p_tx_hash: null
        });
        UI.toast('Crypto deposit rejected.', 'success');
        modal.close();
        load();
      } catch (e) {
        err.textContent = UI.apiErrorMessage(e);
        this.disabled = false;
      }
    });
  }

  function updateStatus(t) {
    if (!t) return;
    if (t.type === 'crypto') {
      verifyDeposit(t);
      return;
    }

    const modal = UI.openModal(
      '<div class="field"><label>New status</label><select class="select" id="st-status">' +
        STATUSES.map(function (s) {
          return '<option value="' + s + '"' + (s === t.status ? ' selected' : '') + '>' + UI.typeLabel(s) + '</option>';
        }).join('') +
      '</select></div><div class="form-error" id="st-error"></div>',
      { title: 'Update Status — ' + t.reference, footer: '<button class="btn btn-outline" data-cancel>Cancel</button><button class="btn btn-primary" data-save>Update</button>' }
    );
    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);
    modal.footer.querySelector('[data-save]').addEventListener('click', async function () {
      this.disabled = true;
      try {
        await adminApi('admin_update_deposit_status', {
          p_deposit_id: t.id,
          p_status: document.getElementById('st-status').value
        });
        UI.toast('Deposit status updated.', 'success');
        modal.close();
        load();
      } catch (e) {
        document.getElementById('st-error').textContent = UI.apiErrorMessage(e);
        this.disabled = false;
      }
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

  async function initAssetFilter() {
    try {
      const config = await adminApi('admin_get_deposit_config');
      const assets = Array.from(new Set((config.assets || []).map(function (a) { return a.asset; }).filter(Boolean))).sort();
      const select = document.getElementById('f-asset');
      select.innerHTML = '<option value="">All assets</option>' + assets.map(function (asset) {
        return '<option value="' + UI.escapeHtml(asset) + '">' + UI.escapeHtml(asset) + '</option>';
      }).join('');
    } catch (e) {
      console.error('Failed to load assets:', e);
    }
  }

  await initAssetFilter();
  await load();
  PageLoader.hide();
})();
