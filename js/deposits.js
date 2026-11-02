// Sagroeurope — Deposits module with configurable payment methods and crypto deposits
(async function () {
  await AppShell.init({ title: 'Deposits' });
  const user = Auth.user;
  if (!user) return;

  const DEFAULT_INSTRUCTIONS = 'Choose a deposit method, complete the payment, and keep the reference for your records. Crypto deposits are credited after confirmation and verification.';

  const FALLBACK_CONFIG = {
    enabled: true,
    instructions: DEFAULT_INSTRUCTIONS,
    methods: [
      { code: 'google_pay', kind: 'wallet', label: 'Google Pay', description: 'Pay instantly with Google Pay', icon: '📱', enabled: true, sort_order: 10, min_amount: 1, max_amount: 10000, currencies: ['EUR', 'USD'], instructions: 'Complete the payment in the Google Pay sheet. Your deposit is credited after the payment is confirmed.' },
      { code: 'apple_pay', kind: 'wallet', label: 'Apple Pay', description: 'Pay instantly with Apple Pay', icon: '🍎', enabled: true, sort_order: 20, min_amount: 1, max_amount: 10000, currencies: ['EUR', 'USD'], instructions: 'Complete the payment in the Apple Pay sheet. Your deposit is credited after the payment is confirmed.' }
    ],
    assets: []
  };

  const state = {
    step: 1,
    accounts: [],
    selectedAccount: null,
    selectedCurrency: 'EUR',
    amount: 0,
    selectedMethod: null,
    selectedAsset: null,
    requestId: null,
    config: FALLBACK_CONFIG,
    paymentMethods: [],
    historyRows: [],
    deposit: null
  };

  function newRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    return 'dep-' + Date.now() + '-' + Math.random().toString(36).slice(2);
  }

  function resetRequest() {
    state.requestId = null;
  }

  function normalizeConfig(raw) {
    const cfg = raw || {};
    return {
      enabled: cfg.enabled !== false,
      instructions: cfg.instructions || DEFAULT_INSTRUCTIONS,
      methods: Array.isArray(cfg.methods) ? cfg.methods : [],
      assets: Array.isArray(cfg.assets) ? cfg.assets : []
    };
  }

  function accountById(id) {
    return state.accounts.find(function (a) { return a.id === id; });
  }

  function methodByCode(code) {
    return state.paymentMethods.find(function (m) { return m.code === code; });
  }

  function currencyOptions(currency) {
    const codes = Array.from(new Set(['EUR', 'USD', currency].filter(Boolean)));
    return codes.map(function (c) {
      const symbol = APP_CONFIG.currencySymbols[c] || c;
      return '<option value="' + c + '">' + c + ' (' + symbol + ')</option>';
    }).join('');
  }

  function setCurrencyTag(cur) {
    const tag = document.getElementById('d-currency-tag');
    if (!tag) return;
    tag.textContent = (APP_CONFIG.currencySymbols[cur] || cur);
    tag.dataset.cur = cur;
  }

  function syncCurrency(currency) {
    const sel = document.getElementById('d-currency');
    if (!sel) return;
    sel.innerHTML = currencyOptions(currency);
    sel.value = currency;
    state.selectedCurrency = currency;
    setCurrencyTag(currency);
  }

  function assetKey(value) {
    return String(value == null ? '' : value).toUpperCase();
  }

  function assetsForMethod(method) {
    const asset = assetKey(method.asset || method.code);
    return (state.config.assets || []).filter(function (a) {
      return assetKey(a.asset) === asset &&
        a.is_enabled !== false &&
        a.deposit_enabled !== false &&
        a.deposit_address && String(a.deposit_address).trim();
    }).sort(function (a, b) {
      return (a.sort_order || 0) - (b.sort_order || 0) || String(a.network || '').localeCompare(String(b.network || ''));
    });
  }

  function buildMethodList() {
    if (!state.config.enabled) return [];
    const methods = [];
    const covered = {};

    (state.config.methods || []).forEach(function (method) {
      if (!method || method.enabled === false) return;
      const kind = method.kind || 'wallet';
      if (kind === 'crypto') {
        const assets = assetsForMethod(method);
        if (!assets.length) return;
        assets.forEach(function (a) { covered[assetKey(a.asset)] = true; });
        methods.push(Object.assign({}, method, { kind: 'crypto', assets: assets }));
      } else {
        methods.push(Object.assign({}, method, { kind: kind }));
      }
    });

    const extra = {};
    (state.config.assets || []).forEach(function (a) {
      const key = assetKey(a.asset);
      if (!key || covered[key]) return;
      if (a.is_enabled === false || a.deposit_enabled === false) return;
      if (!a.deposit_address || !String(a.deposit_address).trim()) return;
      if (!extra[key]) {
        extra[key] = {
          code: key.toLowerCase(),
          kind: 'crypto',
          asset: key,
          label: a.asset_label || key,
          description: 'Deposit ' + (a.asset_label || key),
          icon: '🪙',
          enabled: true,
          sort_order: 900,
          min_amount: a.deposit_min_amount,
          max_amount: a.deposit_max_amount,
          currencies: [],
          instructions: a.deposit_instructions || state.config.instructions,
          assets: []
        };
      }
      extra[key].assets.push(a);
    });

    Object.keys(extra).forEach(function (key) { methods.push(extra[key]); });

    return methods.sort(function (a, b) {
      return (a.sort_order || 0) - (b.sort_order || 0) || String(a.label || '').localeCompare(String(b.label || ''));
    });
  }

  function supportsCurrency(method) {
    const currencies = method.currencies || [];
    return !currencies.length || currencies.indexOf(state.selectedCurrency) !== -1;
  }

  async function walletAvailable(code) {
    if (!window.PaymentRequest || typeof window.PaymentRequest.canMakePayment !== 'function') {
      return false;
    }
    try {
      if (code === 'google_pay') {
        return await new PaymentRequest([{
          supportedMethods: 'https://google.com/pay',
          data: {
            environment: 'TEST',
            apiVersion: 2,
            apiVersionMinor: 0,
            allowedPaymentMethods: [{
              type: 'CARD',
              parameters: {
                allowedAuthMethods: ['PAN_ONLY', 'CRYPTOGRAM_3DS'],
                allowedCardNetworks: ['VISA', 'MASTERCARD']
              }
            }]
          }
        }]).canMakePayment();
      }
      if (code === 'apple_pay') {
        return await new PaymentRequest([{
          supportedMethods: 'https://apple.com/apple-pay',
          data: {
            version: 3,
            merchantIdentifier: 'merchant.com.sagroeurope',
            merchantCapabilities: ['supports3DS', 'supportsCredit', 'supportsDebit'],
            supportedNetworks: ['visa', 'masterCard', 'amex'],
            countryCode: 'US',
            currencyCode: state.selectedCurrency
          }
        }]).canMakePayment();
      }
    } catch (e) {
      return false;
    }
    return true;
  }

  async function loadConfig() {
    try {
      const raw = await UI.rpc('customer_get_deposit_config');
      state.config = normalizeConfig(raw);
    } catch (e) {
      state.config = normalizeConfig(FALLBACK_CONFIG);
      state.configError = UI.apiErrorMessage(e);
    }
  }

  async function loadAccounts() {
    const { data, error } = await SB.from('accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .order('created_at', { ascending: true });
    if (error) throw error;

    state.accounts = data || [];
    const sel = document.getElementById('d-account');
    const next = document.getElementById('d-amount-next');
    if (!state.accounts.length) {
      sel.innerHTML = '<option value="">No active accounts available</option>';
      sel.disabled = true;
      if (next) next.disabled = true;
      return;
    }

    sel.disabled = false;
    sel.innerHTML = state.accounts.map(function (a) {
      return '<option value="' + a.id + '">' + UI.escapeHtml(a.account_name) + ' · ' +
        UI.escapeHtml(a.account_number) + ' (' + UI.escapeHtml(a.currency) + ')</option>';
    }).join('');

    const first = state.accounts[0];
    state.selectedAccount = first.id;
    syncCurrency(first.currency);
  }

  async function loadHistory() {
    const el = document.getElementById('deposit-history');
    if (!el) return;
    el.innerHTML = '<div class="loading-block"><div class="spinner"></div><span>Loading deposits...</span></div>';

    const [fiatRes, cryptoRes] = await Promise.allSettled([
      SB.from('deposits').select('*').eq('user_id', user.id).order('created_at', { ascending: false }),
      SB.from('crypto_deposits').select('*').eq('user_id', user.id).order('created_at', { ascending: false })
    ]);

    const rows = [];

    if (fiatRes.status === 'fulfilled' && !fiatRes.value.error) {
      (fiatRes.value.data || []).forEach(function (d) {
        rows.push({
          id: d.id,
          type: 'fiat',
          reference: d.reference,
          title: UI.typeLabel(d.payment_method || d.method) + ' deposit',
          amount: UI.money(d.amount, d.currency),
          status: d.status,
          tx_hash: null,
          network: null,
          asset: null,
          created_at: d.created_at
        });
      });
    }

    if (cryptoRes.status === 'fulfilled' && !cryptoRes.value.error) {
      (cryptoRes.value.data || []).forEach(function (d) {
        const cryptoAmount = d.amount_crypto != null ? d.amount_crypto : d.amount;
        const amountText = Number(cryptoAmount).toLocaleString('en-US', { maximumFractionDigits: 8 }) + ' ' + (d.asset || '');
        rows.push({
          id: d.id,
          type: 'crypto',
          reference: d.reference,
          title: (d.asset || 'Crypto') + ' deposit',
          amount: amountText,
          fiat: d.amount_fiat != null ? UI.money(d.amount_fiat, d.currency) : '',
          status: d.status,
          tx_hash: d.tx_hash || null,
          network: d.network || null,
          asset: d.asset || null,
          created_at: d.created_at
        });
      });
    }

    if (!rows.length) {
      state.historyRows = [];
      el.innerHTML = UI.emptyState('No deposits yet');
      return;
    }

    rows.sort(function (a, b) { return new Date(b.created_at) - new Date(a.created_at); });
    state.historyRows = rows;

    el.innerHTML = '<div class="tx-list">' + rows.map(function (d) {
      const canSubmitHash = d.type === 'crypto' && d.status === 'pending' && !d.tx_hash;
      const subParts = [d.reference];
      if (d.network) subParts.push(String(d.network).toUpperCase());
      subParts.push(UI.timeAgo(d.created_at));
      const hashLine = d.tx_hash
        ? '<div class="tx-sub tx-hash-line">Tx: ' + UI.escapeHtml(d.tx_hash) + '</div>'
        : '';
      return '<div class="tx-item deposit-history-item">' +
        '<div class="tx-icon">' + ICONS.deposits + '</div>' +
        '<div class="tx-info"><div class="tx-title">' + UI.escapeHtml(d.title) + '</div>' +
        '<div class="tx-sub">' + UI.escapeHtml(subParts.join(' · ')) + '</div>' + hashLine + '</div>' +
        '<div class="deposit-history-side">' +
          '<div class="tx-amount text-success">+' + UI.escapeHtml(d.amount) + '</div>' +
          (d.fiat ? '<div class="tx-sub">' + UI.escapeHtml(d.fiat) + '</div>' : '') +
          UI.badge(d.status) +
          (canSubmitHash ? '<button class="btn btn-outline btn-sm mt-2" data-tx-deposit="' + UI.escapeHtml(d.id) + '">Add transaction hash</button>' : '') +
        '</div>' +
      '</div>';
    }).join('') + '</div>';

    el.querySelectorAll('[data-tx-deposit]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        const row = state.historyRows.find(function (r) { return r.id === btn.getAttribute('data-tx-deposit'); });
        if (row) openTxHashModal(row);
      });
    });
  }

  function paymentError(message) {
    const el = document.getElementById('payment-error');
    if (el) el.textContent = message || '';
  }

  async function loadPaymentMethods() {
    const grid = document.getElementById('payment-methods-grid');
    if (!grid) return;

    if (!state.config.enabled) {
      state.paymentMethods = [];
      grid.innerHTML = UI.emptyState('Deposits are temporarily unavailable. Please check back later.');
      const next = document.getElementById('d-method-next');
      if (next) next.disabled = true;
      return;
    }

    const methods = buildMethodList().filter(supportsCurrency);
    const checked = await Promise.all(methods.map(async function (method) {
      let available = true;
      let status = 'available';

      if (method.kind === 'wallet' && (method.code === 'google_pay' || method.code === 'apple_pay')) {
        available = await walletAvailable(method.code);
        if (!available) status = 'unavailable';
      } else if (method.kind === 'crypto') {
        available = !!(method.assets && method.assets.length);
        if (!available) status = 'unconfigured';
      }

      return Object.assign({}, method, { available: available, status: status });
    }));

    state.paymentMethods = checked;

    if (state.selectedMethod && !checked.some(function (m) { return m.code === state.selectedMethod && m.available; })) {
      state.selectedMethod = null;
    }

    if (!checked.length) {
      grid.innerHTML = UI.emptyState('No deposit methods are available for this account currency.');
      const next = document.getElementById('d-method-next');
      if (next) next.disabled = true;
      return;
    }

    grid.innerHTML = checked.map(function (method) {
      const disabled = !method.available;
      const statusClass = method.available ? 'available' : 'unavailable';
      let statusText = 'Available';
      if (!method.available) {
        statusText = method.status === 'unconfigured' ? 'Not configured yet' : 'Unavailable in this browser';
      }
      const networkText = method.kind === 'crypto' && method.assets
        ? '<div class="payment-method-networks">' + method.assets.map(function (a) {
            return '<span>' + UI.escapeHtml(a.network_label || String(a.network || '').toUpperCase()) + '</span>';
          }).join('') + '</div>'
        : '';
      return '<div class="payment-method-card ' + (disabled ? 'disabled ' : '') + statusClass + '" data-method="' + UI.escapeHtml(method.code) + '">' +
        '<div class="payment-method-icon">' + UI.escapeHtml(method.icon || '•') + '</div>' +
        '<div class="payment-method-info">' +
          '<div class="payment-method-label">' + UI.escapeHtml(method.label || method.code) + '</div>' +
          '<div class="payment-method-description">' + UI.escapeHtml(method.description || '') + '</div>' +
          networkText +
          '<div class="payment-method-status ' + statusClass + '">' + UI.escapeHtml(statusText) + '</div>' +
        '</div>' +
        '<input type="radio" name="payment-method" value="' + UI.escapeHtml(method.code) + '" ' + (disabled ? 'disabled' : '') +
          (state.selectedMethod === method.code ? ' checked' : '') + '>' +
      '</div>';
    }).join('');

    grid.querySelectorAll('.payment-method-card:not(.disabled)').forEach(function (card) {
      card.addEventListener('click', function () {
        grid.querySelectorAll('.payment-method-card').forEach(function (c) { c.classList.remove('selected'); });
        this.classList.add('selected');
        state.selectedMethod = this.dataset.method;
        state.selectedAsset = null;
        resetRequest();
        const next = document.getElementById('d-method-next');
        if (next) next.disabled = false;
      });
    });

    const next = document.getElementById('d-method-next');
    if (next) next.disabled = !state.selectedMethod;
  }

  function showStep(n) {
    state.step = n;
    [1, 2, 3, 4].forEach(function (s) {
      const el = document.getElementById('deposit-step-' + s);
      if (el) el.classList.toggle('hide', s !== n);
    });

    const indicator = document.querySelector('#deposit-step-' + n + ' .step-indicator');
    if (indicator) {
      indicator.querySelectorAll('.step-number').forEach(function (p, i) {
        p.classList.toggle('active', i === n - 1);
        p.classList.toggle('done', i < n - 1);
      });
      indicator.querySelectorAll('.step-title').forEach(function (p, i) {
        p.classList.toggle('active', i === n - 1);
        p.classList.toggle('done', i < n - 1);
      });
    }

    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function instructionsFor(method, asset) {
    return (asset && asset.deposit_instructions) || (method && method.instructions) || state.config.instructions || DEFAULT_INSTRUCTIONS;
  }

  function renderWalletStep(method) {
    const container = document.getElementById('deposit-payment-process');
    if (!container) return;
    const acc = accountById(state.selectedAccount) || {};

    container.innerHTML =
      '<div class="card">' +
        '<div class="card-header"><h3 class="card-title">Pay with ' + UI.escapeHtml(method.label) + '</h3></div>' +
        '<div class="card-body">' +
          '<div class="payment-summary">' +
            '<div class="summary-row"><span>Amount</span><strong>' + UI.money(state.amount, state.selectedCurrency) + '</strong></div>' +
            '<div class="summary-row"><span>Method</span><strong>' + UI.escapeHtml(method.label) + '</strong></div>' +
            '<div class="summary-row"><span>Deposit to</span><strong>' + UI.escapeHtml(acc.account_name || '—') + '</strong></div>' +
          '</div>' +
          '<div class="deposit-instructions mt-3"><strong>Instructions</strong><p>' + UI.escapeHtml(instructionsFor(method)) + '</p></div>' +
          '<div class="form-error" id="payment-error"></div>' +
          '<button class="btn btn-primary btn-block" id="pay-btn" style="margin-top:16px">' +
            '<span class="pay-btn-icon">' + UI.escapeHtml(method.icon || '') + '</span> Pay ' + UI.money(state.amount, state.selectedCurrency) + ' with ' + UI.escapeHtml(method.label) +
          '</button>' +
        '</div>' +
      '</div>';

    document.getElementById('pay-btn').addEventListener('click', async function () {
      const btn = this;
      paymentError('');
      try {
        const pin = await UI.promptPin({
          title: 'Confirm Deposit',
          message: 'Enter your 4-digit security PIN to authorize this deposit of ' + UI.money(state.amount, state.selectedCurrency) + '.'
        });
        btn.disabled = true;
        btn.textContent = 'Processing...';
        if (!state.requestId) state.requestId = newRequestId();

        const deposit = await UI.rpc('create_customer_deposit', {
          p_user_id: user.id,
          p_account_id: state.selectedAccount,
          p_amount: state.amount,
          p_currency: state.selectedCurrency,
          p_method: method.backend_method || 'card',
          p_note: method.label + ' deposit',
          p_pin: pin,
          p_method_code: method.code,
          p_request_id: state.requestId
        });

        state.requestId = null;
        finishDeposit(deposit, method, null);
      } catch (e) {
        btn.disabled = false;
        btn.innerHTML = '<span class="pay-btn-icon">' + UI.escapeHtml(method.icon || '') + '</span> Pay ' +
          UI.money(state.amount, state.selectedCurrency) + ' with ' + UI.escapeHtml(method.label);
        if (e && e.message !== 'CANCELLED') paymentError(UI.apiErrorMessage(e));
      }
    });
  }

  function renderCryptoStep(method) {
    const container = document.getElementById('deposit-payment-process');
    if (!container) return;
    const assets = method.assets || [];
    if (!assets.length) {
      container.innerHTML = '<div class="card"><div class="card-body">' + UI.emptyState('This cryptocurrency is not configured yet.') + '</div></div>';
      return;
    }

    container.innerHTML =
      '<div class="card">' +
        '<div class="card-header"><h3 class="card-title">' + UI.escapeHtml(method.label) + ' Deposit</h3></div>' +
        '<div class="card-body">' +
          '<div class="field"><label>Network</label><select class="select" id="crypto-network">' +
            assets.map(function (a) {
              return '<option value="' + UI.escapeHtml(a.network) + '">' + UI.escapeHtml(a.network_label || a.network) + '</option>';
            }).join('') +
          '</select></div>' +
          '<div class="field"><label>Amount (' + UI.escapeHtml(method.asset || method.code) + ')</label>' +
            '<div class="amount-field"><input type="number" class="input" id="crypto-amount" min="0" step="any" placeholder="0">' +
            '<span class="currency-tag">' + UI.escapeHtml(method.asset || method.code) + '</span></div></div>' +
          '<div class="deposit-limits" id="crypto-limits"></div>' +
          '<div class="deposit-instructions mt-2"><strong>Instructions</strong><p>' + UI.escapeHtml(instructionsFor(method, assets[0])) + '</p></div>' +
          '<div class="form-error" id="payment-error"></div>' +
          '<button class="btn btn-primary btn-block" id="crypto-continue" style="margin-top:16px">Generate Deposit Address</button>' +
        '</div>' +
      '</div>';

    const networkSel = document.getElementById('crypto-network');
    const amountInput = document.getElementById('crypto-amount');
    const limits = document.getElementById('crypto-limits');

    function selectedAsset() {
      return assets.find(function (a) { return a.network === networkSel.value; }) || assets[0];
    }

    function renderLimits() {
      const a = selectedAsset();
      const min = a.deposit_min_amount != null ? a.deposit_min_amount : a.min_amount;
      const max = a.deposit_max_amount != null ? a.deposit_max_amount : a.max_amount;
      amountInput.min = min != null ? min : 0;
      amountInput.step = 'any';
      limits.innerHTML = '<span>Minimum: ' + UI.escapeHtml(String(min != null ? min : 0)) + ' ' + UI.escapeHtml(a.asset) + '</span>' +
        (max != null ? '<span>Maximum: ' + UI.escapeHtml(String(max)) + ' ' + UI.escapeHtml(a.asset) + '</span>' : '');
    }

    networkSel.addEventListener('change', function () {
      state.selectedAsset = selectedAsset();
      renderLimits();
      const instructions = container.querySelector('.deposit-instructions p');
      if (instructions) instructions.textContent = instructionsFor(method, selectedAsset());
    });

    state.selectedAsset = selectedAsset();
    renderLimits();

    document.getElementById('crypto-continue').addEventListener('click', async function () {
      const btn = this;
      const asset = selectedAsset();
      const amount = Number(amountInput.value);
      const min = asset.deposit_min_amount != null ? asset.deposit_min_amount : asset.min_amount;
      const max = asset.deposit_max_amount != null ? asset.deposit_max_amount : asset.max_amount;
      paymentError('');

      if (!amount || amount <= 0) { paymentError('Enter a valid amount.'); return; }
      if (min != null && amount < min) { paymentError('Minimum deposit is ' + min + ' ' + asset.asset + '.'); return; }
      if (max != null && amount > max) { paymentError('Maximum deposit is ' + max + ' ' + asset.asset + '.'); return; }

      try {
        const pin = await UI.promptPin({
          title: 'Confirm Deposit',
          message: 'Enter your 4-digit security PIN to generate your ' + asset.asset + ' deposit address.'
        });
        btn.disabled = true;
        btn.textContent = 'Generating...';
        if (!state.requestId) state.requestId = newRequestId();

        const deposit = await UI.rpc('create_crypto_deposit', {
          p_user_id: user.id,
          p_account_id: state.selectedAccount,
          p_asset: asset.asset,
          p_network: asset.network,
          p_amount: amount,
          p_pin: pin,
          p_request_id: state.requestId
        });

        state.requestId = null;
        state.selectedAsset = asset;
        finishDeposit(deposit, method, asset);
      } catch (e) {
        btn.disabled = false;
        btn.textContent = 'Generate Deposit Address';
        if (e && e.message !== 'CANCELLED') paymentError(UI.apiErrorMessage(e));
      }
    });
  }

  function renderBankStep(method) {
    const container = document.getElementById('deposit-payment-process');
    if (!container) return;
    container.innerHTML =
      '<div class="card">' +
        '<div class="card-header"><h3 class="card-title">' + UI.escapeHtml(method.label) + '</h3></div>' +
        '<div class="card-body">' +
          '<div class="payment-summary">' +
            '<div class="summary-row"><span>Amount</span><strong>' + UI.money(state.amount, state.selectedCurrency) + '</strong></div>' +
            '<div class="summary-row"><span>Method</span><strong>' + UI.escapeHtml(method.label) + '</strong></div>' +
          '</div>' +
          '<div class="deposit-instructions mt-3"><strong>Instructions</strong><p>' + UI.escapeHtml(instructionsFor(method)) + '</p></div>' +
          '<div class="form-error" id="payment-error"></div>' +
          '<button class="btn btn-primary btn-block" id="bank-continue" style="margin-top:16px">Generate Deposit Reference</button>' +
        '</div>' +
      '</div>';

    document.getElementById('bank-continue').addEventListener('click', async function () {
      const btn = this;
      paymentError('');
      try {
        const pin = await UI.promptPin({
          title: 'Confirm Deposit',
          message: 'Enter your 4-digit security PIN to create this deposit request.'
        });
        btn.disabled = true;
        btn.textContent = 'Creating...';
        if (!state.requestId) state.requestId = newRequestId();
        const deposit = await UI.rpc('create_customer_deposit', {
          p_user_id: user.id,
          p_account_id: state.selectedAccount,
          p_amount: state.amount,
          p_currency: state.selectedCurrency,
          p_method: method.backend_method || 'bank_transfer',
          p_note: method.label + ' deposit',
          p_pin: pin,
          p_method_code: method.code,
          p_request_id: state.requestId
        });
        state.requestId = null;
        finishDeposit(deposit, method, null);
      } catch (e) {
        btn.disabled = false;
        btn.textContent = 'Generate Deposit Reference';
        if (e && e.message !== 'CANCELLED') paymentError(UI.apiErrorMessage(e));
      }
    });
  }

  function renderPaymentStep() {
    const method = methodByCode(state.selectedMethod);
    if (!method) return;
    if (method.kind === 'crypto') {
      renderCryptoStep(method);
    } else if (method.kind === 'bank') {
      renderBankStep(method);
    } else {
      renderWalletStep(method);
    }
  }

  function renderQR(text) {
    const el = document.getElementById('deposit-qr');
    if (!el) return;
    if (typeof qrcode !== 'function') {
      el.innerHTML = '<div class="qr-unavailable">QR code unavailable</div>';
      return;
    }
    try {
      const qr = qrcode(0, 'M');
      qr.addData(text);
      qr.make();
      el.innerHTML = qr.createSvgTag({ cellSize: 4, margin: 8, scalable: true });
    } catch (e) {
      el.innerHTML = '<div class="qr-unavailable">QR code unavailable</div>';
    }
  }

  function finishDeposit(deposit, method, asset) {
    state.deposit = deposit || {};
    const complete = document.getElementById('deposit-complete');
    if (!complete) return;

    const data = state.deposit;
    const isCrypto = method && method.kind === 'crypto';
    const reference = data.reference || '—';
    const status = data.status || 'pending';
    const instructions = instructionsFor(method, asset);
    const amountText = isCrypto
      ? (Number(data.amount || data.amount_crypto || 0).toLocaleString('en-US', { maximumFractionDigits: 8 }) + ' ' + (data.asset || (asset && asset.asset) || ''))
      : UI.money(state.amount, state.selectedCurrency);

    let html =
      '<div class="card">' +
        '<div class="card-body">' +
          '<div class="success-icon">✓</div>' +
          '<h3 class="card-title">' + (isCrypto ? 'Deposit address ready' : 'Deposit submitted') + '</h3>' +
          '<p class="text-muted">' + (isCrypto
            ? 'Send the exact amount to the address below, then submit the transaction hash for verification.'
            : 'Your deposit request has been submitted successfully.') + '</p>' +
          '<div class="detail-grid">' +
            '<div class="detail-item"><div class="k">Reference</div><div class="v">' + UI.escapeHtml(reference) + '</div></div>' +
            '<div class="detail-item"><div class="k">Method</div><div class="v">' + UI.escapeHtml(method ? method.label : 'Deposit') + '</div></div>' +
            '<div class="detail-item"><div class="k">Amount</div><div class="v">' + UI.escapeHtml(amountText) + '</div></div>' +
            '<div class="detail-item"><div class="k">Status</div><div class="v" id="deposit-status-badge">' + UI.badge(status) + '</div></div>' +
          '</div>';

    if (isCrypto) {
      const address = data.address || (asset && asset.deposit_address) || '';
      const networkLabel = (asset && (asset.network_label || asset.network)) || data.network || '';
      const tag = data.address_tag || (asset && asset.deposit_address_tag);
      const min = asset && (asset.deposit_min_amount != null ? asset.deposit_min_amount : asset.min_amount);
      const max = asset && (asset.deposit_max_amount != null ? asset.deposit_max_amount : asset.max_amount);

      html +=
        '<div class="crypto-deposit-layout mt-3">' +
          '<div class="qr-panel">' +
            '<div class="qr-code" id="deposit-qr"></div>' +
            '<div class="qr-caption">Scan to deposit</div>' +
          '</div>' +
          '<div class="crypto-details">' +
            '<div class="detail-grid">' +
              '<div class="detail-item"><div class="k">Network</div><div class="v">' + UI.escapeHtml(String(networkLabel).toUpperCase()) + '</div></div>' +
              '<div class="detail-item"><div class="k">Minimum</div><div class="v">' + UI.escapeHtml(String(min != null ? min : 0)) + ' ' + UI.escapeHtml(data.asset || (asset && asset.asset) || '') + '</div></div>' +
              (max != null ? '<div class="detail-item"><div class="k">Maximum</div><div class="v">' + UI.escapeHtml(String(max)) + ' ' + UI.escapeHtml(data.asset || (asset && asset.asset) || '') + '</div></div>' : '') +
            '</div>' +
            '<div class="field mt-2"><label>Wallet address</label>' +
              '<div class="address-container">' +
                '<input type="text" class="input" id="deposit-address" value="' + UI.escapeHtml(address) + '" readonly>' +
                '<button class="btn btn-outline btn-sm" id="copy-deposit-address">Copy</button>' +
              '</div>' +
            '</div>' +
            (tag ? '<div class="field"><label>Address tag / memo</label><input type="text" class="input" value="' + UI.escapeHtml(tag) + '" readonly></div>' : '') +
            '<div class="deposit-instructions mt-2"><strong>Instructions</strong><p>' + UI.escapeHtml(instructions) + '</p></div>' +
            '<div class="tx-hash-form mt-3">' +
              '<label for="deposit-tx-hash">Transaction hash</label>' +
              '<div class="address-container">' +
                '<input type="text" class="input" id="deposit-tx-hash" placeholder="Paste the transaction hash after sending">' +
                '<button class="btn btn-primary btn-sm" id="submit-tx-hash">Submit</button>' +
              '</div>' +
              '<div class="form-note">Your deposit is credited only after the transaction is confirmed and verified.</div>' +
              '<div class="form-error" id="tx-hash-error"></div>' +
            '</div>' +
          '</div>' +
        '</div>';
    } else {
      html += '<div class="deposit-instructions mt-3"><strong>Instructions</strong><p>' + UI.escapeHtml(instructions) + '</p></div>';
    }

    html +=
          '<div class="receipt-actions mt-3">' +
            '<button class="btn btn-primary" id="deposit-again">Make another deposit</button>' +
            '<a href="transactions.html" class="btn btn-outline">View transactions</a>' +
          '</div>' +
        '</div>' +
      '</div>';

    complete.innerHTML = html;

    if (isCrypto) {
      renderQR(data.address || (asset && asset.deposit_address) || '');
      const copyBtn = document.getElementById('copy-deposit-address');
      if (copyBtn) {
        copyBtn.addEventListener('click', async function () {
          const input = document.getElementById('deposit-address');
          const ok = await UI.copyText(input.value);
          UI.toast(ok ? 'Address copied to clipboard' : 'Unable to copy address', ok ? 'success' : 'warning');
        });
      }
      const submitBtn = document.getElementById('submit-tx-hash');
      if (submitBtn) {
        submitBtn.addEventListener('click', async function () {
          const hashEl = document.getElementById('deposit-tx-hash');
          const errEl = document.getElementById('tx-hash-error');
          const hash = hashEl.value.trim();
          errEl.textContent = '';
          if (hash.length < 8) { errEl.textContent = 'Enter a valid transaction hash.'; return; }
          submitBtn.disabled = true;
          submitBtn.textContent = 'Submitting...';
          try {
            const res = await UI.rpc('customer_submit_crypto_tx', {
              p_deposit_id: data.id,
              p_tx_hash: hash
            });
            state.deposit.status = (res && res.status) || 'pending_verification';
            state.deposit.tx_hash = (res && res.tx_hash) || hash;
            const badge = document.getElementById('deposit-status-badge');
            if (badge) badge.innerHTML = UI.badge(state.deposit.status);
            submitBtn.textContent = 'Submitted';
            hashEl.disabled = true;
            submitBtn.disabled = true;
            errEl.textContent = '';
            UI.toast('Transaction hash submitted for verification.', 'success');
            loadHistory();
          } catch (e) {
            submitBtn.disabled = false;
            submitBtn.textContent = 'Submit';
            errEl.textContent = UI.apiErrorMessage(e);
          }
        });
      }
    }

    document.getElementById('deposit-again').addEventListener('click', function () {
      state.deposit = null;
      state.selectedMethod = null;
      state.selectedAsset = null;
      state.requestId = null;
      state.amount = 0;
      document.getElementById('d-amount').value = '';
      document.getElementById('deposit-payment-process').innerHTML = '';
      const next = document.getElementById('d-method-next');
      if (next) next.disabled = true;
      showStep(1);
      loadPaymentMethods();
    });

    showStep(4);
    loadHistory();
  }

  function openTxHashModal(row) {
    const modal = UI.openModal(
      '<div class="field"><label for="modal-tx-hash">Transaction hash</label>' +
        '<input type="text" class="input" id="modal-tx-hash" placeholder="Paste the transaction hash">' +
        '<div class="form-note">Deposit ' + UI.escapeHtml(row.reference) + ' · ' + UI.escapeHtml(row.amount) + '</div>' +
      '</div>' +
      '<div class="form-error" id="modal-tx-error"></div>',
      {
        title: 'Submit transaction hash',
        footer: '<button class="btn btn-outline" id="modal-tx-cancel">Cancel</button>' +
          '<button class="btn btn-primary" id="modal-tx-submit">Submit for verification</button>'
      }
    );

    modal.footer.querySelector('#modal-tx-cancel').addEventListener('click', modal.close);
    modal.footer.querySelector('#modal-tx-submit').addEventListener('click', async function () {
      const btn = this;
      const hash = modal.body.querySelector('#modal-tx-hash').value.trim();
      const err = modal.body.querySelector('#modal-tx-error');
      err.textContent = '';
      if (hash.length < 8) { err.textContent = 'Enter a valid transaction hash.'; return; }
      btn.disabled = true;
      btn.textContent = 'Submitting...';
      try {
        await UI.rpc('customer_submit_crypto_tx', {
          p_deposit_id: row.id,
          p_tx_hash: hash
        });
        modal.close();
        UI.toast('Transaction hash submitted for verification.', 'success');
        loadHistory();
      } catch (e) {
        btn.disabled = false;
        btn.textContent = 'Submit for verification';
        err.textContent = UI.apiErrorMessage(e);
      }
    });
  }

  document.getElementById('d-account').addEventListener('change', function () {
    const acc = accountById(this.value);
    if (!acc) return;
    state.selectedAccount = acc.id;
    syncCurrency(acc.currency);
    resetRequest();
    loadPaymentMethods();
  });

  document.getElementById('d-currency').addEventListener('change', function () {
    state.selectedCurrency = this.value;
    setCurrencyTag(this.value);
    resetRequest();
    loadPaymentMethods();
  });

  document.getElementById('d-amount-next').addEventListener('click', function () {
    const err = document.getElementById('d-amount-error');
    err.textContent = '';
    const accountId = document.getElementById('d-account').value;
    const amount = Number(document.getElementById('d-amount').value);
    const currency = document.getElementById('d-currency').value;
    const acc = accountById(accountId);

    if (!state.config.enabled) { err.textContent = 'Deposits are temporarily unavailable.'; return; }
    if (!acc) { err.textContent = 'Select an account.'; return; }
    if (!amount || amount <= 0) { err.textContent = 'Enter a valid deposit amount.'; return; }
    if (currency !== acc.currency) { err.textContent = 'Deposit currency must match the selected account.'; return; }

    state.selectedAccount = accountId;
    state.amount = amount;
    state.selectedCurrency = currency;
    state.selectedMethod = null;
    state.selectedAsset = null;
    resetRequest();

    loadPaymentMethods();
    showStep(2);
  });

  document.getElementById('d-method-back').addEventListener('click', function () {
    resetRequest();
    showStep(1);
  });

  document.getElementById('d-method-next').addEventListener('click', function () {
    if (!state.selectedMethod) return;
    showStep(3);
    renderPaymentStep();
  });

  try {
    const results = await Promise.allSettled([loadConfig(), loadAccounts()]);
    if (results[0].status === 'rejected') {
      state.config = normalizeConfig(FALLBACK_CONFIG);
    }
    if (results[1].status === 'rejected') {
      const history = document.getElementById('deposit-history');
      if (history) history.innerHTML = UI.emptyState('Could not load your accounts. Please try again.');
      const err = document.getElementById('d-amount-error');
      if (err) err.textContent = 'Could not load your accounts. Please refresh the page.';
    }
    await loadPaymentMethods();
    loadHistory();
  } catch (e) {
    UI.toast(UI.apiErrorMessage(e), 'error');
    const history = document.getElementById('deposit-history');
    if (history) history.innerHTML = UI.emptyState('Could not load deposits');
  } finally {
    PageLoader.hide();
  }
})();
