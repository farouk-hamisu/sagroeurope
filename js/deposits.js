// Sagroeurope — Deposits module with multi-step payment flow
(async function () {
  await AppShell.init({ title: 'Deposits' });
  const user = Auth.user;

  let accounts = [];
  let state = {
    step: 1,
    accounts: [],
    balances: {},
    selectedAccount: null,
    selectedCurrency: 'EUR',
    amount: 0,
    selectedMethod: null,
    paymentData: {}
  };

  // Payment method configurations
  const PAYMENT_METHODS = {
    google_pay: {
      id: 'google_pay',
      label: 'Google Pay',
      icon: '📱',
      description: 'Pay with Google Pay',
      currencies: ['EUR', 'USD'],
      checkAvailability: async () => {
        if (window.PaymentRequest && window.PaymentRequest.canMakePayment) {
          try {
            const supported = await new PaymentRequest([{
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
              }]).canMakePayment();
              return supported;
          } catch (e) {
            return false;
          }
        }
        return false;
      },
      processPayment: async (amount, currency) => {
        return processGooglePayPayment(amount, state.selectedCurrency);
      }
    },
    apple_pay: {
      id: 'apple_pay',
      label: 'Apple Pay',
      icon: '🍎',
      description: 'Pay with Apple Pay',
      currencies: ['EUR', 'USD'],
      checkAvailability: async () => {
        if (window.PaymentRequest && window.PaymentRequest.canMakePayment) {
          try {
            const supported = await new PaymentRequest([{
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
            return supported;
          } catch (e) {
            return false;
          }
        }
        return false;
      },
      processPayment: async (amount, currency) => {
        return processApplePayPayment(amount, state.selectedCurrency);
      }
    },
    usdt: {
      id: 'usdt',
      label: 'USDT',
      icon: '💲',
      description: 'Tether (USDT) - TRC-20 / ERC-20',
      currencies: ['USD'],
      networks: [
        { id: 'trc20', label: 'TRC-20 (Tron)', address: 'TXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' },
        { id: 'erc20', label: 'ERC-20 (Ethereum)', address: '0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' }
      ],
      processPayment: async (amount, currency, network) => {
        return initiateCryptoDeposit('USDT', amount, state.selectedCurrency, network);
      }
    },
    bitcoin: {
      id: 'bitcoin',
      label: 'Bitcoin (BTC)',
      icon: '₿',
      description: 'Bitcoin (BTC) - Bitcoin Network',
      currencies: ['BTC'],
      processPayment: async (amount, currency) => {
        return initiateBitcoinDeposit(amount, state.selectedCurrency);
      }
    }
  };

  async function loadAccounts() {
    const { data, error } = await SB.from('accounts').select('*').eq('user_id', user.id).eq('status', 'active');
    if (error) throw error;
    state.accounts = data || [];
    const sel = document.getElementById('d-account');
    sel.innerHTML = state.accounts.map(function (a) {
      return '<option value="' + a.id + '">' + UI.escapeHtml(a.account_name) + ' · ' + UI.escapeHtml(a.account_number) + ' (' + UI.escapeHtml(a.currency) + ')</option>';
    }).join('');
    if (state.accounts[0]) {
      state.selectedAccount = state.accounts[0].id;
      state.selectedCurrency = state.accounts[0].currency;
      setCurrencyTag(state.accounts[0].currency);
    }
    sel.addEventListener('change', function () {
      const acc = state.accounts.find(function (a) { return a.id === sel.value; });
      if (acc) {
        state.selectedAccount = acc.id;
        state.selectedCurrency = acc.currency;
        setCurrencyTag(acc.currency);
        loadPaymentMethods();
      }
    });
  }

  function setCurrencyTag(cur) {
    document.getElementById('d-currency-tag').textContent = (APP_CONFIG.currencySymbols[cur] || cur);
    document.getElementById('d-currency-tag').dataset.cur = cur;
  }

  async function loadHistory() {
    const el = document.getElementById('deposit-history');
    try {
      const { data, error } = await SB.from('deposits').select('*').eq('user_id', user.id).order('created_at', { ascending: false });
      if (error) throw error;
      if (!data.length) { el.innerHTML = UI.emptyState('No deposits yet'); return; }
      el.innerHTML = '<div class="tx-list">' + data.map(function (d) {
        return '<div class="tx-item">' +
          '<div class="tx-icon">' + ICONS.deposits + '</div>' +
          '<div class="tx-info"><div class="tx-title">' + UI.escapeHtml(UI.typeLabel(d.method)) + ' deposit</div>' +
          '<div class="tx-sub">' + UI.escapeHtml(d.reference) + ' · ' + UI.timeAgo(d.created_at) + '</div></div>' +
          '<div style="text-align:right;white-space:nowrap"><div class="tx-amount text-success">+' + UI.money(d.amount, d.currency) + '</div>' + UI.badge(d.status) + '</div>' +
        '</div>';
      }).join('') + '</div>';
    } catch (e) {
      el.innerHTML = UI.emptyState('Could not load deposits');
    }
  }

  function loadPaymentMethods() {
    const grid = document.getElementById('payment-methods-grid');
    if (!grid) return;

    const currency = state.selectedCurrency;
    const availableMethods = Object.values(PAYMENT_METHODS).filter(m => m.currencies.includes(state.selectedCurrency));

    // Check availability for each method
    const methodsWithAvailability = await Promise.all(availableMethods.map(async (method) => {
      let available = true;
      let status = 'available';
      
      if (method.checkAvailability) {
        try {
          available = await method.checkAvailability();
          status = available ? 'available' : 'unavailable';
        } catch (e) {
          available = false;
          status = 'unavailable';
        }
      }

      // Filter by currency
      if (method.currencies && !method.currencies.includes(state.selectedCurrency)) {
        available = false;
        status = 'currency_mismatch';
      }

      return { ...method, available, status };
    }));

    grid.innerHTML = availableMethods.map(method => {
      const disabled = !method.available;
      const statusClass = method.status === 'available' ? '' : method.status === 'unavailable' ? 'unavailable' : 'currency_mismatch';
      const statusText = method.status === 'available' ? 'Available' : method.status === 'unavailable' ? 'Unavailable in your region' : 'Not available for selected currency';
      
      return `
        <div class="payment-method-card ${disabled ? 'disabled' : ''} ${statusClass}" data-method="${method.id}">
          <div class="payment-method-icon">${method.icon}</div>
          <div class="payment-method-info">
            <div class="payment-method-label">${method.label}</div>
            <div class="payment-method-description">${method.description}</div>
            <div class="payment-method-status ${method.available ? 'available' : 'unavailable'}">${statusText}</div>
          </div>
          <input type="radio" name="payment-method" value="${method.id}" ${disabled ? 'disabled' : ''} ${state.selectedMethod === method.id ? 'checked' : ''}>
        </div>
      `;
    }).join('');

    // Add event listeners
    grid.querySelectorAll('.payment-method-card:not(.disabled)').forEach(card => {
      card.addEventListener('click', function() {
        document.querySelectorAll('.payment-method-card').forEach(c => c.classList.remove('selected'));
        this.classList.add('selected');
        state.selectedMethod = this.dataset.method;
        document.getElementById('d-method-next').disabled = false;
      });
    });
  }

  function showStep(n) {
    state.step = n;
    [1, 2, 3, 4].forEach(function (s) {
      const el = document.getElementById('deposit-step-' + s);
      el.classList.toggle('hide', s !== n);
      document.querySelectorAll('.step-indicator .step-number').forEach((p, i) => {
        const stepNum = i + 1;
        p.classList.toggle('active', stepNum === n);
        p.classList.toggle('done', stepNum < n);
      });
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function setCurrencyTag(cur) {
    document.getElementById('d-currency-tag').textContent = (APP_CONFIG.currencySymbols[cur] || cur);
    document.getElementById('d-currency-tag').dataset.cur = cur;
  }

  async function loadHistory() {
    const el = document.getElementById('deposit-history');
    try {
      const { data, error } = await SB.from('deposits').select('*').eq('user_id', user.id).order('created_at', { ascending: false });
      if (error) throw error;
      if (!data.length) { el.innerHTML = UI.emptyState('No deposits yet'); return; }
      el.innerHTML = '<div class="tx-list">' + data.map(function (d) {
        return '<div class="tx-item">' +
          '<div class="tx-icon">' + ICONS.deposits + '</div>' +
          '<div class="tx-info"><div class="tx-title">' + UI.escapeHtml(UI.typeLabel(d.method)) + ' deposit</div>' +
          '<div class="tx-sub">' + UI.escapeHtml(d.reference) + ' · ' + UI.timeAgo(d.created_at) + '</div></div>' +
          '<div style="text-align:right;white-space:nowrap"><div class="tx-amount text-success">+' + UI.money(d.amount, d.currency) + '</div>' + UI.badge(d.status) + '</div>' +
        '</div>';
      }).join('') + '</div>';
    } catch (e) {
      el.innerHTML = UI.emptyState('Could not load deposits');
    }
  }

  // Step 1: Amount
  document.getElementById('d-account').addEventListener('change', function () {
    const acc = state.accounts.find(function (a) { return a.id === this.value; });
    if (acc) {
      state.selectedAccount = acc.id;
      state.selectedCurrency = acc.currency;
      setCurrencyTag(acc.currency);
    }
    loadPaymentMethods();
  });

  document.getElementById('d-currency').addEventListener('change', function () {
    state.selectedCurrency = this.value;
    setCurrencyTag(this.value);
    loadPaymentMethods();
  });

  function setCurrencyTag(cur) {
    document.getElementById('d-currency-tag').textContent = (APP_CONFIG.currencySymbols[cur] || cur);
    document.getElementById('d-currency-tag').dataset.cur = cur;
  }

  document.getElementById('d-amount-next').addEventListener('click', function () {
    const err = document.getElementById('d-amount-error');
    err.textContent = '';
    const accountId = document.getElementById('d-account').value;
    const amount = Number(document.getElementById('d-amount').value);
    const currency = document.getElementById('d-currency').value;
    
    if (!accountId) { err.textContent = 'Select an account.'; return; }
    if (!amount || amount <= 0) { err.textContent = 'Enter a valid deposit amount.'; return; }
    
    state.selectedAccount = accountId;
    state.amount = amount;
    state.selectedCurrency = currency;
    state.selectedCurrency = currency;
    
    loadPaymentMethods();
    showStep(2);
  });

  // Step 2: Payment Method
  document.getElementById('d-method-back').addEventListener('click', function () { showStep(1); });
  
  document.getElementById('d-method-next').addEventListener('click', function () {
    if (!state.selectedMethod) return;
    showStep(3);
    renderPaymentStep();
  });

  // Step 3: Payment Processing
  async function renderPaymentStep() {
    const container = document.getElementById('deposit-payment-process');
    const method = PAYMENT_METHODS[state.selectedMethod];
    
    if (!method) return;

    if (method.id === 'google_pay' || method.id === 'apple_pay') {
      // Digital wallet payment
      container.innerHTML = `
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Pay with ${method.label}</h3>
          </div>
          <div class="card-body">
            <div class="payment-summary">
              <div class="summary-row"><span>Amount</span><strong id="pay-amount">${UI.money(state.amount, state.selectedCurrency)}</strong></div>
              <div class="summary-row"><span>Method</span><strong>${method.label}</strong></div>
            </div>
            <div class="form-error" id="pay-error"></div>
            <button class="btn btn-primary btn-block" id="pay-btn" style="margin-top:16px">
              <span class="pay-btn-icon">${method.icon}</span> Pay ${UI.money(state.amount, state.selectedCurrency)} with ${method.label}
            </button>
          </div>
        `;
        
        document.getElementById('pay-btn').addEventListener('click', async function() {
          const btn = this;
          const errEl = document.getElementById('pay-error');
          errEl.textContent = '';
          
          btn.disabled = true;
          btn.textContent = 'Processing...';
          
          try {
            const result = await method.processPayment(state.amount, state.selectedCurrency);
            if (result.success) {
              UI.toast('Payment successful!', 'success');
              setTimeout(() => window.location.href = 'deposits.html', 1500);
            } else {
              throw new Error(result.error || 'Payment failed');
            }
          } catch (e) {
            errEl.textContent = UI.apiErrorMessage(e);
            btn.disabled = false;
            btn.innerHTML = '<span class="pay-btn-icon">' + method.icon + '</span> Pay ' + UI.money(state.amount, state.selectedCurrency) + ' with ' + method.label;
          }
        });
        
      } else if (method.id === 'usdt') {
        // USDT deposit
        const networks = method.networks;
        let selectedNetwork = networks[0].id;
        
        container.innerHTML = `
          <div class="card">
            <div class="card-header">
              <h3 class="card-title">USDT Deposit</h3>
            </div>
            <div class="card-body">
              <div class="field">
                <label>Network</label>
                <select class="select" id="usdt-network">
                  ${method.networks.map(n => `<option value="${n.id}">${n.label}</option>`).join('')}
                </select>
              </div>
              <div class="field">
                <label>Amount (USDT)</label>
                <div class="amount-field">
                  <input type="number" class="input" id="usdt-amount" min="1" step="1" placeholder="0">
                  <span class="currency-tag">USDT</span>
                </div>
              </div>
              <div class="form-error" id="usdt-error"></div>
              <button class="btn btn-primary btn-block" id="usdt-continue">Generate Deposit Address</button>
            </div>
        `;
        
        document.getElementById('usdt-network').addEventListener('change', function() {
          selectedNetwork = this.value;
        });
        
        document.getElementById('usdt-continue').addEventListener('click', async function() {
          const btn = this;
          const errEl = document.getElementById('usdt-error');
          const amount = Number(document.getElementById('usdt-amount').value);
          const network = document.getElementById('usdt-network').value;
          
          if (!amount || amount <= 0) { errEl.textContent = 'Enter a valid amount.'; return; }
          
          btn.disabled = true;
          btn.textContent = 'Generating...';
          
          try {
            const result = await method.processPayment(amount, 'USDT', network);
            if (result.success && result.address) {
              showUSDTDepositAddress(result.address, result.network, amount);
            } else {
              throw new Error(result.error || 'Failed to generate address');
            }
          } catch (e) {
            document.getElementById('usdt-error').textContent = UI.apiErrorMessage(e);
            btn.disabled = false;
            btn.textContent = 'Generate Deposit Address';
          }
        });
        
      } else if (method.id === 'bitcoin') {
        // Bitcoin deposit
        container.innerHTML = `
          <div class="card">
            <div class="card-header">
              <h3 class="card-title">Bitcoin Deposit</h3>
            </div>
            <div class="card-body">
              <div class="field">
                <label>Amount (BTC)</label>
                <div class="amount-field">
                  <input type="number" class="input" id="btc-amount" min="0.0001" step="0.00000001" placeholder="0.00000000">
                  <span class="currency-tag">₿</span>
                </div>
              </div>
              <div class="form-error" id="btc-error"></div>
              <button class="btn btn-primary btn-block" id="btc-continue">Generate Deposit Address</button>
            </div>
          </div>
        `;
        
        document.getElementById('btc-continue').addEventListener('click', async function() {
          const btn = this;
          const errEl = document.getElementById('btc-error');
          const amount = Number(document.getElementById('btc-amount').value);
          
          if (!amount || amount <= 0) { errEl.textContent = 'Enter a valid amount.'; return; }
          
          btn.disabled = true;
          btn.textContent = 'Generating...';
          
          try {
            const result = await method.processPayment(amount, 'BTC');
            if (result.success && result.address) {
              showBTCDepositAddress(result.address, amount);
            } else {
              throw new Error(result.error || 'Failed to generate address');
            }
          } catch (e) {
            document.getElementById('btc-error').textContent = UI.apiErrorMessage(e);
            btn.disabled = false;
            btn.textContent = 'Generate Deposit Address';
          }
        });
      }
    }

    function showUSDTDepositAddress(address, network, amount) {
      const container = document.getElementById('deposit-payment-process');
      container.innerHTML = `
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">USDT Deposit Address</h3>
          </div>
          <div class="card-body">
            <div class="crypto-deposit-info">
              <div class="crypto-icon usdt">💲</div>
              <h3>Send USDT (${network.toUpperCase()})</h3>
              <div class="address-container">
                <input type="text" class="input" id="usdt-deposit-address" value="${address}" readonly>
                <button class="btn btn-outline btn-sm" onclick="copyToClipboard('usdt-deposit-address')">Copy</button>
              </div>
              <div class="amount-info">
                <span class="amount-label">Amount to send:</span>
                <span class="amount-value">${amount} USDT</span>
              </div>
              <div class="network-info">
                <strong>Network:</strong> ${network.toUpperCase()}
              </div>
              <div class="warning-box">
                <strong>⚠ Important:</strong> Only send USDT via ${network.toUpperCase()} network. Sending via other networks will result in permanent loss of funds.
              </div>
              <div class="amount-info">
                <span class="amount-label">Minimum deposit:</span>
                <span class="amount-value">1 USDT</span>
              </div>
            </div>
            <div class="receipt-actions">
              <button class="btn btn-primary" onclick="copyToClipboard('usdt-deposit-address')">Copy Address</button>
              <a href="deposits.html" class="btn btn-outline">Back to Deposits</a>
            </div>
          </div>
        `;
      }

      function showBTCDepositAddress(address, amount) {
        const container = document.getElementById('deposit-payment-process');
        container.innerHTML = `
          <div class="card">
            <div class="card-header">
              <h3 class="card-title">Bitcoin Deposit Address</h3>
            </div>
            <div class="card-body">
              <div class="crypto-deposit-info">
                <div class="crypto-icon btc">₿</div>
                <h3>Send Bitcoin (BTC)</h3>
                <div class="address-container">
                  <input type="text" class="input" id="btc-deposit-address" value="${address}" readonly>
                  <button class="btn btn-outline btn-sm" onclick="copyToClipboard('btc-deposit-address')">Copy</button>
                </div>
                <div class="amount-info">
                  <span class="amount-label">Amount to send:</span>
                  <span class="amount-value">${amount} BTC</span>
                </div>
                <div class="warning-box">
                  <strong>⚠ Important:</strong> Only send BTC via Bitcoin network. Minimum deposit: 0.0001 BTC.
                </div>
              </div>
              <div class="receipt-actions">
                <button class="btn btn-primary" onclick="copyToClipboard('btc-deposit-address')">Copy Address</button>
                <a href="deposits.html" class="btn btn-outline">Back to Deposits</a>
              </div>
            </div>
          </div>
        `;
      }

      function copyToClipboard(elementId) {
        const el = document.getElementById(elementId);
        navigator.clipboard.writeText(el.value).then(() => {
          UI.toast('Address copied to clipboard', 'success');
        });
      }

      // Google Pay
      async function processGooglePayPayment(amount, currency) {
        if (!window.PaymentRequest) {
          throw new Error('Payment Request API not supported');
        }
        
        const paymentDetails = {
          total: {
            label: 'Sagroeurope Deposit',
            amount: { currency: currency, value: amount.toFixed(2) }
          },
          displayItems: [
            { label: 'Deposit Amount', amount: { currency: currency, value: amount.toFixed(2) } }
          ]
        };
        
        const paymentRequest = new PaymentRequest([
          {
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
        ], paymentDetails);
        
        try {
          const paymentResponse = await paymentRequest.show();
          // Process payment response
          const result = await paymentResponse.complete('success');
          return { success: true };
        } catch (e) {
          if (e.name === 'AbortError') {
            throw new Error('Payment cancelled');
          }
          throw e;
        }
      }

      // Apple Pay
      async function processApplePayPayment(amount, currency) {
        if (!window.PaymentRequest || !window.ApplePaySession) {
          throw new Error('Apple Pay not supported');
        }
        
        const paymentRequest = {
          countryCode: 'US',
          currencyCode: currency,
          total: {
            label: 'Sagroeurope Deposit',
            amount: amount.toFixed(2),
            type: 'final'
          },
          merchantCapabilities: ['supports3DS', 'supportsCredit', 'supportsDebit'],
          supportedNetworks: ['visa', 'masterCard', 'amex'],
          merchantIdentifier: 'merchant.com.sagroeurope'
        };
        
        const session = new ApplePaySession(3, paymentRequest);
        
        session.onpaymentauthorized = async (event) => {
          // Process payment
          return { status: ApplePaySession.STATUS_SUCCESS };
        };
        
        session.begin();
        
        return new Promise((resolve) => {
          session.onpaymentauthorized = (event) => {
            resolve({ success: true });
          };
        });
      }

      // USDT Deposit
      async function initiateCryptoDeposit(asset, amount, currency, network) {
        const { data, error } = await SB.rpc('create_crypto_deposit', {
          p_user_id: user.id,
          p_asset: asset,
          p_network: network,
          p_amount: amount
        });
        
        if (error) throw error;
        return data;
      }

      // Bitcoin Deposit
      async function initiateBitcoinDeposit(amount, currency) {
        const { data, error } = await SB.rpc('create_bitcoin_deposit', {
          p_user_id: user.id,
          p_amount: amount,
          p_currency: currency
        });
        
        if (error) throw error;
        return data;
      }

      function copyToClipboard(elementId) {
        const el = document.getElementById(elementId);
        navigator.clipboard.writeText(el.value).then(() => {
          UI.toast('Address copied to clipboard', 'success');
        });
      }

      // Load data
      async function loadData() {
        try {
          await loadAccounts();
          await loadHistory();
        } catch (e) {
          UI.toast(UI.apiErrorMessage(e), 'error');
        }
        PageLoader.hide();
      }

      // Initialize
      document.addEventListener('DOMContentLoaded', loadData);
    })();
  }