// Sagroeurope — Admin deposit settings
(async function () {
  const admin = await AdminAuth.requireAuth();
  if (!admin) return;
  renderAdminShell('Deposit Settings');

  if (!AdminAuth.can('deposits.manage')) {
    document.getElementById('page-root').innerHTML = UI.emptyState('You do not have permission to manage deposit settings');
    PageLoader.hide();
    return;
  }

  let config = null;

  function num(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
  }

  function valueOrEmpty(value) {
    return value === null || value === undefined ? '' : String(value);
  }

  async function load() {
    try {
      config = await adminApi('admin_get_deposit_config');
      renderGeneral();
      renderMethods();
      renderAssets();
    } catch (e) {
      const message = UI.apiErrorMessage(e);
      ['general-settings', 'methods-table', 'assets-table'].forEach(function (id) {
        const el = document.getElementById(id);
        if (el) el.innerHTML = UI.emptyState(message);
      });
      UI.toast(message, 'error');
    } finally {
      PageLoader.hide();
    }
  }

  function renderGeneral() {
    const el = document.getElementById('general-settings');
    const enabled = config && config.enabled !== false;
    el.innerHTML =
      '<div class="switch-row">' +
        '<input type="checkbox" id="deposit-enabled"' + (enabled ? ' checked' : '') + '>' +
        '<label for="deposit-enabled">Allow customers to make deposits</label>' +
      '</div>' +
      '<div class="field mt-2">' +
        '<label for="deposit-instructions">Global deposit instructions</label>' +
        '<textarea class="textarea" id="deposit-instructions" rows="4" placeholder="Shown on the customer deposit page">' +
          UI.escapeHtml((config && config.instructions) || '') +
        '</textarea>' +
        '<div class="hint">This notice appears above the payment methods. Method and network instructions override it where provided.</div>' +
      '</div>';
  }

  function renderMethods() {
    const el = document.getElementById('methods-table');
    const methods = (config && config.methods) || [];
    if (!methods.length) {
      el.innerHTML = UI.emptyState('No deposit methods configured');
      return;
    }

    el.innerHTML = '<table class="table mobile-cards">' +
      '<thead><tr><th>Method</th><th>Code</th><th>Kind</th><th>Limits</th><th>Currencies</th><th>Status</th><th>Actions</th></tr></thead><tbody>' +
      methods.map(function (m) {
        const isCrypto = m.kind === 'crypto';
        const hasReadyAsset = !isCrypto || (config.assets || []).some(function (a) {
          return String(a.asset || '').toUpperCase() === String(m.asset || '').toUpperCase() &&
            a.is_enabled !== false && a.deposit_enabled !== false &&
            a.deposit_address && String(a.deposit_address).trim() !== '';
        });
        const active = m.enabled !== false && hasReadyAsset;
        const status = active
          ? '<span class="badge badge-success">Active</span>'
          : '<span class="badge badge-neutral">' + (m.enabled === false ? 'Disabled' : 'No network ready') + '</span>';
        const limits = UI.money(m.min_amount || 0, '') + (m.max_amount != null ? ' – ' + UI.money(m.max_amount, '') : ' – No max');
        return '<tr>' +
          '<td data-label="Method"><span class="cell-main">' + UI.escapeHtml(m.icon || '') + ' ' + UI.escapeHtml(m.label) + '</span>' +
            (m.description ? '<div class="cell-sub">' + UI.escapeHtml(m.description) + '</div>' : '') + '</td>' +
          '<td data-label="Code"><span class="deposit-method-code">' + UI.escapeHtml(m.code) + '</span></td>' +
          '<td data-label="Kind">' + UI.escapeHtml(UI.typeLabel(m.kind)) + (m.asset ? ' <span class="cell-sub">' + UI.escapeHtml(m.asset) + '</span>' : '') + '</td>' +
          '<td data-label="Limits">' + limits + '</td>' +
          '<td data-label="Currencies">' + UI.escapeHtml((m.currencies || []).join(', ')) + '</td>' +
          '<td data-label="Status">' + status + (isCrypto && !hasReadyAsset ? '<div class="deposit-warning">Configure a network address first</div>' : '') + '</td>' +
          '<td data-label="Actions"><button class="row-action" data-edit-method="' + UI.escapeHtml(m.code) + '" title="Edit method">' + ICONS.edit + '</button></td>' +
        '</tr>';
      }).join('') + '</tbody></table>';

    el.querySelectorAll('[data-edit-method]').forEach(function (button) {
      button.addEventListener('click', function () {
        const code = button.getAttribute('data-edit-method');
        const method = methods.find(function (m) { return m.code === code; });
        openMethodModal(method || null);
      });
    });
  }

  function renderAssets() {
    const el = document.getElementById('assets-table');
    const assets = (config && config.assets) || [];
    if (!assets.length) {
      el.innerHTML = UI.emptyState('No crypto networks configured');
      return;
    }

    el.innerHTML = '<table class="table mobile-cards">' +
      '<thead><tr><th>Asset / Network</th><th>Labels</th><th>Deposit Address</th><th>Limits</th><th>Rate (USD)</th><th>Status</th><th>Actions</th></tr></thead><tbody>' +
      assets.map(function (a) {
        const hasAddress = a.deposit_address && String(a.deposit_address).trim() !== '';
        const active = a.is_enabled !== false && a.deposit_enabled !== false && hasAddress;
        let status = '<span class="badge badge-neutral">Disabled</span>';
        if (active) status = '<span class="badge badge-success">Active</span>';
        else if (a.deposit_enabled !== false && !hasAddress) status = '<span class="badge badge-warning">Needs address</span>';
        const key = String(a.asset || '') + '|' + String(a.network || '');
        return '<tr>' +
          '<td data-label="Asset / Network"><span class="cell-main">' + UI.escapeHtml(a.asset) + '</span><div class="cell-sub">' + UI.escapeHtml(a.network) + '</div></td>' +
          '<td data-label="Labels">' + UI.escapeHtml(a.asset_label || a.asset) + '<div class="cell-sub">' + UI.escapeHtml(a.network_label || a.network) + '</div></td>' +
          '<td data-label="Deposit Address"><span class="deposit-address-cell" title="' + UI.escapeHtml(a.deposit_address || '') + '">' +
            (hasAddress ? UI.escapeHtml(a.deposit_address) : '<span class="deposit-warning">Not configured</span>') + '</span></td>' +
          '<td data-label="Limits">' + UI.escapeHtml(String(a.deposit_min_amount == null ? 0 : a.deposit_min_amount)) +
            (a.deposit_max_amount != null ? ' – ' + UI.escapeHtml(String(a.deposit_max_amount)) : ' – No max') + '</td>' +
          '<td data-label="Rate">' + UI.escapeHtml(valueOrEmpty(a.rate_usd)) + '</td>' +
          '<td data-label="Status">' + status + '</td>' +
          '<td data-label="Actions"><button class="row-action" data-edit-asset="' + UI.escapeHtml(key) + '" title="Edit network">' + ICONS.edit + '</button></td>' +
        '</tr>';
      }).join('') + '</tbody></table>';

    el.querySelectorAll('[data-edit-asset]').forEach(function (button) {
      button.addEventListener('click', function () {
        const key = button.getAttribute('data-edit-asset');
        const asset = assets.find(function (a) { return String(a.asset || '') + '|' + String(a.network || '') === key; });
        openAssetModal(asset || null);
      });
    });
  }

  function openMethodModal(method) {
    const isEdit = !!method;
    const m = method || {
      code: '', kind: 'wallet', asset: '', backend_method: 'card', label: '', description: '',
      icon: '', enabled: true, sort_order: 0, min_amount: 1, max_amount: 10000,
      currencies: ['EUR', 'USD'], instructions: '', config: {}
    };
    const modal = UI.openModal(
      '<div class="form-grid deposit-config-modal">' +
        '<div class="field"><label class="field-required" for="m-code">Code</label>' +
          '<input class="input" id="m-code" value="' + UI.escapeHtml(m.code) + '"' + (isEdit ? ' readonly' : '') + ' placeholder="e.g. sepa_bank">' +
          '<div class="hint">Lowercase letters, numbers and underscores only.</div></div>' +
        '<div class="field"><label for="m-kind">Kind</label><select class="select" id="m-kind">' +
          ['wallet', 'crypto', 'bank'].map(function (k) { return '<option value="' + k + '"' + (k === m.kind ? ' selected' : '') + '>' + UI.typeLabel(k) + '</option>'; }).join('') +
        '</select></div>' +
        '<div class="field"><label for="m-asset">Crypto asset</label><input class="input" id="m-asset" value="' + UI.escapeHtml(m.asset || '') + '" placeholder="e.g. USDT"><div class="hint">Required when kind is Crypto.</div></div>' +
        '<div class="field"><label for="m-backend">Backend method</label><input class="input" id="m-backend" value="' + UI.escapeHtml(m.backend_method || '') + '" placeholder="e.g. card"></div>' +
        '<div class="field"><label class="field-required" for="m-label">Label</label><input class="input" id="m-label" value="' + UI.escapeHtml(m.label || '') + '"></div>' +
        '<div class="field"><label for="m-icon">Icon</label><input class="input" id="m-icon" value="' + UI.escapeHtml(m.icon || '') + '" placeholder="Optional emoji or short text"></div>' +
        '<div class="field"><label for="m-description">Description</label><input class="input" id="m-description" value="' + UI.escapeHtml(m.description || '') + '"></div>' +
        '<div class="field"><label for="m-sort">Sort order</label><input class="input" id="m-sort" type="number" value="' + num(m.sort_order, 0) + '"></div>' +
        '<div class="field"><label for="m-min">Minimum amount</label><input class="input" id="m-min" type="number" min="0" step="any" value="' + num(m.min_amount, 0) + '"></div>' +
        '<div class="field"><label for="m-max">Maximum amount</label><input class="input" id="m-max" type="number" min="0" step="any" value="' + (m.max_amount == null ? '' : num(m.max_amount, '')) + '"></div>' +
        '<div class="field"><label for="m-currencies">Currencies</label><input class="input" id="m-currencies" value="' + UI.escapeHtml((m.currencies || ['EUR', 'USD']).join(', ')) + '"><div class="hint">Comma separated, e.g. EUR, USD.</div></div>' +
        '<div class="field"><label for="m-config">Config JSON</label><textarea class="textarea" id="m-config" rows="3">' + UI.escapeHtml(JSON.stringify(m.config || {}, null, 2)) + '</textarea></div>' +
        '<div class="field field-full"><label for="m-instructions">Instructions</label><textarea class="textarea" id="m-instructions" rows="3">' + UI.escapeHtml(m.instructions || '') + '</textarea></div>' +
        '<div class="field field-full"><label class="switch-row"><input type="checkbox" id="m-enabled"' + (m.enabled !== false ? ' checked' : '') + '> Enabled</label></div>' +
        '<div class="form-error field-full" id="m-error"></div>' +
      '</div>',
      { title: isEdit ? 'Edit Deposit Method' : 'Add Deposit Method', footer: '<button class="btn btn-outline" data-cancel>Cancel</button><button class="btn btn-primary" data-save>Save Method</button>' }
    );
    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);
    modal.footer.querySelector('[data-save]').addEventListener('click', async function () {
      const err = document.getElementById('m-error');
      err.textContent = '';
      const kind = document.getElementById('m-kind').value;
      const code = document.getElementById('m-code').value.trim().toLowerCase();
      const asset = document.getElementById('m-asset').value.trim().toUpperCase();
      const label = document.getElementById('m-label').value.trim();
      const min = Number(document.getElementById('m-min').value);
      const maxRaw = document.getElementById('m-max').value.trim();
      const max = maxRaw === '' ? null : Number(maxRaw);
      const currencies = document.getElementById('m-currencies').value.split(',').map(function (c) { return c.trim().toUpperCase(); }).filter(Boolean);
      let parsedConfig = {};
      try {
        parsedConfig = JSON.parse(document.getElementById('m-config').value.trim() || '{}');
        if (!parsedConfig || typeof parsedConfig !== 'object' || Array.isArray(parsedConfig)) throw new Error('Invalid config');
      } catch (e) {
        err.textContent = 'Config JSON must be a valid object.';
        return;
      }
      if (!/^[a-z0-9_]+$/.test(code)) { err.textContent = 'Code may only contain lowercase letters, numbers and underscores.'; return; }
      if (!label) { err.textContent = 'Label is required.'; return; }
      if (kind === 'crypto' && !asset) { err.textContent = 'A crypto asset is required for crypto methods.'; return; }
      if (!Number.isFinite(min) || min < 0) { err.textContent = 'Minimum amount must be zero or greater.'; return; }
      if (max !== null && (!Number.isFinite(max) || max < min)) { err.textContent = 'Maximum amount must be greater than or equal to the minimum.'; return; }
      if (!currencies.length) { err.textContent = 'Add at least one currency.'; return; }

      const button = this;
      button.disabled = true;
      try {
        await adminApi('admin_save_deposit_method', {
          p_code: code,
          p_kind: kind,
          p_asset: kind === 'crypto' ? asset : null,
          p_backend_method: document.getElementById('m-backend').value.trim() || null,
          p_label: label,
          p_description: document.getElementById('m-description').value.trim() || null,
          p_icon: document.getElementById('m-icon').value.trim() || null,
          p_enabled: document.getElementById('m-enabled').checked,
          p_sort_order: num(document.getElementById('m-sort').value, 0),
          p_min_amount: min,
          p_max_amount: max,
          p_currencies: currencies,
          p_instructions: document.getElementById('m-instructions').value.trim() || null,
          p_config: parsedConfig
        });
        UI.toast('Deposit method saved.', 'success');
        modal.close();
        await load();
      } catch (e) {
        err.textContent = UI.apiErrorMessage(e);
        button.disabled = false;
      }
    });
  }

  function openAssetModal(asset) {
    const isEdit = !!asset;
    const a = asset || {
      asset: '', network: '', asset_label: '', network_label: '', is_enabled: true,
      deposit_enabled: false, deposit_address: '', deposit_address_tag: '',
      deposit_min_amount: 0, deposit_max_amount: null, deposit_instructions: '',
      rate_usd: '', sort_order: 0
    };
    const modal = UI.openModal(
      '<div class="form-grid deposit-config-modal">' +
        '<div class="field"><label class="field-required" for="a-asset">Asset</label>' +
          '<input class="input" id="a-asset" value="' + UI.escapeHtml(a.asset || '') + '"' + (isEdit ? ' readonly' : '') + ' placeholder="e.g. USDT"></div>' +
        '<div class="field"><label class="field-required" for="a-network">Network</label>' +
          '<input class="input" id="a-network" value="' + UI.escapeHtml(a.network || '') + '"' + (isEdit ? ' readonly' : '') + ' placeholder="e.g. trc20"></div>' +
        '<div class="field"><label for="a-asset-label">Asset label</label><input class="input" id="a-asset-label" value="' + UI.escapeHtml(a.asset_label || '') + '"></div>' +
        '<div class="field"><label for="a-network-label">Network label</label><input class="input" id="a-network-label" value="' + UI.escapeHtml(a.network_label || '') + '"></div>' +
        '<div class="field"><label class="field-required" for="a-rate">Rate (USD)</label><input class="input" id="a-rate" type="number" min="0" step="any" value="' + (a.rate_usd == null ? '' : num(a.rate_usd, '')) + '"><div class="hint">Must be greater than zero.</div></div>' +
        '<div class="field"><label for="a-sort">Sort order</label><input class="input" id="a-sort" type="number" value="' + num(a.sort_order, 0) + '"></div>' +
        '<div class="field"><label for="a-min">Deposit minimum</label><input class="input" id="a-min" type="number" min="0" step="any" value="' + num(a.deposit_min_amount, 0) + '"></div>' +
        '<div class="field"><label for="a-max">Deposit maximum</label><input class="input" id="a-max" type="number" min="0" step="any" value="' + (a.deposit_max_amount == null ? '' : num(a.deposit_max_amount, '')) + '"></div>' +
        '<div class="field field-full"><label for="a-address">Deposit address</label><textarea class="textarea" id="a-address" rows="2" placeholder="Network deposit address">' + UI.escapeHtml(a.deposit_address || '') + '</textarea></div>' +
        '<div class="field field-full"><label for="a-tag">Address tag / memo</label><input class="input" id="a-tag" value="' + UI.escapeHtml(a.deposit_address_tag || '') + '"><div class="hint">Optional. Required by some networks such as XRP or XLM.</div></div>' +
        '<div class="field field-full"><label for="a-instructions">Deposit instructions</label><textarea class="textarea" id="a-instructions" rows="3">' + UI.escapeHtml(a.deposit_instructions || '') + '</textarea></div>' +
        '<div class="field"><label class="switch-row"><input type="checkbox" id="a-enabled"' + (a.is_enabled !== false ? ' checked' : '') + '> Asset enabled</label></div>' +
        '<div class="field"><label class="switch-row"><input type="checkbox" id="a-deposit-enabled"' + (a.deposit_enabled !== false ? ' checked' : '') + '> Accept deposits</label></div>' +
        '<div class="form-error field-full" id="a-error"></div>' +
      '</div>',
      { title: isEdit ? 'Edit Crypto Network' : 'Add Crypto Network', footer: '<button class="btn btn-outline" data-cancel>Cancel</button><button class="btn btn-primary" data-save>Save Network</button>' }
    );
    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);
    modal.footer.querySelector('[data-save]').addEventListener('click', async function () {
      const err = document.getElementById('a-error');
      err.textContent = '';
      const assetCode = document.getElementById('a-asset').value.trim().toUpperCase();
      const network = document.getElementById('a-network').value.trim().toLowerCase();
      const address = document.getElementById('a-address').value.trim();
      const rate = Number(document.getElementById('a-rate').value);
      const min = Number(document.getElementById('a-min').value);
      const maxRaw = document.getElementById('a-max').value.trim();
      const max = maxRaw === '' ? null : Number(maxRaw);
      const depositEnabled = document.getElementById('a-deposit-enabled').checked;

      if (!assetCode || !network) { err.textContent = 'Asset and network are required.'; return; }
      if (!Number.isFinite(rate) || rate <= 0) { err.textContent = 'Rate must be greater than zero.'; return; }
      if (!Number.isFinite(min) || min < 0) { err.textContent = 'Deposit minimum must be zero or greater.'; return; }
      if (max !== null && (!Number.isFinite(max) || max < min)) { err.textContent = 'Deposit maximum must be greater than or equal to the minimum.'; return; }
      if (depositEnabled && !address) { err.textContent = 'Enter a deposit address before enabling deposits.'; return; }

      const button = this;
      button.disabled = true;
      try {
        await adminApi('admin_save_crypto_deposit_asset', {
          p_asset: assetCode,
          p_network: network,
          p_asset_label: document.getElementById('a-asset-label').value.trim() || null,
          p_network_label: document.getElementById('a-network-label').value.trim() || null,
          p_is_enabled: document.getElementById('a-enabled').checked,
          p_deposit_enabled: depositEnabled,
          p_deposit_address: address || null,
          p_deposit_address_tag: document.getElementById('a-tag').value.trim() || null,
          p_deposit_min_amount: min,
          p_deposit_max_amount: max,
          p_deposit_instructions: document.getElementById('a-instructions').value.trim() || null,
          p_rate_usd: rate,
          p_sort_order: num(document.getElementById('a-sort').value, 0)
        });
        UI.toast('Crypto network saved.', 'success');
        modal.close();
        await load();
      } catch (e) {
        err.textContent = UI.apiErrorMessage(e);
        button.disabled = false;
      }
    });
  }

  document.getElementById('btn-save-general').addEventListener('click', async function () {
    const err = document.getElementById('general-error');
    const button = this;
    err.textContent = '';
    button.disabled = true;
    try {
      await adminApi('admin_update_deposit_general', {
        p_enabled: document.getElementById('deposit-enabled').checked,
        p_instructions: document.getElementById('deposit-instructions').value.trim()
      });
      UI.toast('Deposit settings saved.', 'success');
      await load();
    } catch (e) {
      err.textContent = UI.apiErrorMessage(e);
    } finally {
      button.disabled = false;
    }
  });

  document.getElementById('btn-add-method').addEventListener('click', function () {
    openMethodModal(null);
  });

  document.getElementById('btn-add-asset').addEventListener('click', function () {
    openAssetModal(null);
  });

  await load();
})();
