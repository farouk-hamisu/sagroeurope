// Sagroeurope — Local transfer module
(async function () {
  await AppShell.init({ title: 'Local Transfer' });
  const user = Auth.user;

  const state = { step: 1, accounts: [], balances: {}, beneficiaries: [], recipient: null };

  function showStep(n) {
    state.step = n;
    [1, 2, 3, 4].forEach(function (s) {
      const el = document.getElementById('step-' + s);
      el.classList.toggle('hide', s !== n);
      document.querySelectorAll('.step-pill[data-step="' + s + '"]').forEach(function (p) {
        p.classList.toggle('active', s === n);
        p.classList.toggle('done', s < n);
      });
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function load() {
    try {
      // Check outgoing transfers enabled
      const profile = await Auth.fetchProfile();
      const banner = document.getElementById('outgoing-banner');
      if (profile.outgoing_transfers_enabled === false) {
        banner.classList.remove('hide');
        document.getElementById('outgoing-banner-reason').textContent =
          (profile.outgoing_transfers_disabled_reason ? 'Reason: ' + profile.outgoing_transfers_disabled_reason : 'Please contact support for details.');
      } else {
        banner.classList.add('hide');
      }

      const [accRes, benRes] = await Promise.all([
        SB.from('accounts').select('*').eq('user_id', user.id).eq('status', 'active'),
        SB.from('beneficiaries').select('*').eq('user_id', user.id).eq('is_international', false)
      ]);
      if (accRes.error) throw accRes.error;
      if (benRes.error) throw benRes.error;

      state.accounts = accRes.data || [];
      state.beneficiaries = benRes.data || [];

      const balRes = await SB.from('account_balances').select('*').in('account_id', state.accounts.map(function (a) { return a.id; }));
      if (balRes.error) throw balRes.error;
      (balRes.data || []).forEach(function (b) { state.balances[b.account_id] = b; });

      // beneficiary select
      const sel = document.getElementById('beneficiary-select');
      sel.innerHTML = '<option value="">Select a saved beneficiary...</option>' + state.beneficiaries.map(function (b) {
        return '<option value="' + b.id + '">' + UI.escapeHtml(b.name) + ' · ' + UI.escapeHtml(b.account_number) + '</option>';
      }).join('');

      // from account select — EUR and USD accounts
      const eurUsdAccounts = state.accounts.filter(function (a) { return a.currency === 'EUR' || a.currency === 'USD'; });
      const fromSel = document.getElementById('t-from');
      fromSel.innerHTML = eurUsdAccounts.map(function (a) {
        const sym = APP_CONFIG.currencySymbols[a.currency] || a.currency;
        return '<option value="' + a.id + '">' + UI.escapeHtml(a.account_name) + ' · ' + UI.escapeHtml(a.account_number) + ' (' + sym + ')</option>';
      }).join('');

      // currency field — EUR and USD
      const curSel = document.getElementById('r-currency');
      curSel.innerHTML = '<option value="EUR">EUR (€)</option><option value="USD">USD ($)</option>';
      curSel.value = 'EUR';

      updateBalance();
      // load transfer history into recent tab? kept simple: no
    } catch (e) {
      UI.toast(UI.apiErrorMessage(e), 'error');
    }
  }

  function updateBalance() {
    const fromId = document.getElementById('t-from').value;
    const acc = state.accounts.find(function (a) { return a.id === fromId; });
    const b = state.balances[fromId];
    if (acc && b) {
      document.getElementById('t-balance').textContent = UI.money(b.available_balance, acc.currency);
      document.getElementById('t-currency-tag').textContent = (APP_CONFIG.currencySymbols[acc.currency] || acc.currency);
      document.getElementById('t-currency-tag').dataset.cur = acc.currency;
    } else {
      document.getElementById('t-balance').textContent = '—';
    }
  }

  // --- Step 1: recipient ---
  document.getElementById('step1-next').addEventListener('click', async function () {
    const err = document.getElementById('step1-error');
    err.textContent = '';
    const benId = document.getElementById('beneficiary-select').value;
    if (benId) {
      const b = state.beneficiaries.find(function (x) { return x.id === benId; });
      state.recipient = { name: b.name, account: b.account_number, bank: b.bank_name || 'Sagroeurope', currency: b.currency || 'EUR' };
    } else {
      const name = document.getElementById('r-name').value.trim();
      const account = document.getElementById('r-account').value.trim();
const bank = document.getElementById('r-bank').value.trim() || 'Sagroeurope';
      const currency = document.getElementById('r-currency').value;
      if (!name || !account) { err.textContent = 'Enter the recipient name and account number.'; return; }
      if (!/^\d+$/.test(account) || account.length < 6) { err.textContent = 'Enter a valid account number.'; return; }
      state.recipient = { name: name, account: account, bank: bank, currency: currency };
    }
    document.getElementById('rv-name').textContent = state.recipient.name;
    document.getElementById('rv-account').textContent = state.recipient.account;
    document.getElementById('rv-bank').textContent = state.recipient.bank;
    showStep(2);
  });

  document.getElementById('btn-new-benef').addEventListener('click', function () {
    document.getElementById('benef-form').classList.toggle('hide');
  });

  document.getElementById('btn-save-benef').addEventListener('click', async function () {
    const name = document.getElementById('r-name').value.trim();
    const account = document.getElementById('r-account').value.trim();
    const bank = document.getElementById('r-bank').value.trim() || 'Sagroeurope';
    if (!name || !account) { UI.toast('Enter name and account number.', 'warning'); return; }
    const { error } = await SB.from('beneficiaries').insert({
      user_id: user.id, name: name, account_number: account, bank_name: bank,
      currency: document.getElementById('r-currency').value, is_international: false
    });
    if (error) { UI.toast(UI.apiErrorMessage(error), 'error'); return; }
    UI.toast('Beneficiary saved.', 'success');
    document.getElementById('benef-form').classList.add('hide');
    await load();
  });

  document.getElementById('t-from').addEventListener('change', updateBalance);
  document.getElementById('t-amount').addEventListener('input', function () {
    const amt = Number(this.value) || 0;
    const cur = document.getElementById('t-currency-tag').dataset.cur || 'EUR';
    document.getElementById('t-total').textContent = UI.money(amt, cur);
  });

  // --- Step 2 ---
  document.getElementById('step2-next').addEventListener('click', function () {
    const err = document.getElementById('step2-error');
    err.textContent = '';
    const fromId = document.getElementById('t-from').value;
    const amount = Number(document.getElementById('t-amount').value);
    if (!fromId) { err.textContent = 'Select an account to transfer from.'; return; }
    if (!amount || amount <= 0) { err.textContent = 'Enter a valid amount.'; return; }
    const b = state.balances[fromId];
    if (b && amount > Number(b.available_balance)) { err.textContent = 'Insufficient funds for this transfer.'; return; }
    const acc = state.accounts.find(function (a) { return a.id === fromId; });
    document.getElementById('rv-from').textContent = acc.account_name + ' · ' + acc.account_number;
    document.getElementById('rv-amount').textContent = UI.money(amount, acc.currency);
    document.getElementById('rv-desc').textContent = document.getElementById('t-desc').value.trim() || '—';
    showStep(3);
  });

  document.getElementById('step2-back').addEventListener('click', function () { showStep(1); });

  // --- Step 3 ---
  document.getElementById('step3-next').addEventListener('click', async function () {
    const btn = this;
    const fromId = document.getElementById('t-from').value;
    const amount = Number(document.getElementById('t-amount').value);
    const acc = state.accounts.find(function (a) { return a.id === fromId; });
    const desc = document.getElementById('t-desc').value.trim();

    // try to resolve internal recipient (uses SECURITY DEFINER RPC to bypass RLS)
    let internalRecipient = null;
    try {
      const lookup = await SB.rpc('lookup_account_user_id', { p_account_number: state.recipient.account });
      if (!lookup.error && lookup.data) internalRecipient = lookup.data;
    } catch (_) { /* not an internal account */ }

    try {
      const pin = await UI.promptPin({
        title: 'Confirm Transfer',
        message: 'Enter your 4-digit security PIN to authorize this transfer of ' + UI.money(amount, acc.currency) + ' to ' + state.recipient.name + '.'
      });
      btn.disabled = true;
      btn.textContent = 'Processing...';
      const transfer = await UI.rpc('create_local_transfer', {
        p_user_id: user.id,
        p_from_account_id: fromId,
        p_recipient_name: state.recipient.name,
        p_recipient_account_number: state.recipient.account,
        p_recipient_bank: state.recipient.bank,
        p_amount: amount,
        p_currency: acc.currency,
        p_description: desc || null,
        p_internal_recipient: internalRecipient || null,
        p_pin: pin
      });
      
      // Populate professional receipt
      const now = new Date();
      document.getElementById('receipt-ref').textContent = transfer.reference;
      document.getElementById('receipt-date').textContent = UI.formatDateTime(now);
      document.getElementById('receipt-from-name').textContent = acc.account_name;
      document.getElementById('receipt-from-account').textContent = acc.account_number;
      document.getElementById('receipt-to-name').textContent = state.recipient.name;
      document.getElementById('receipt-bank').textContent = state.recipient.bank;
      document.getElementById('receipt-account').textContent = state.recipient.account;
      document.getElementById('receipt-amount').textContent = UI.money(amount, acc.currency);
      document.getElementById('receipt-fee').textContent = UI.money(0, acc.currency);
      document.getElementById('receipt-total').textContent = UI.money(amount, acc.currency);
      document.getElementById('receipt-desc').textContent = desc || '—';
      
      // Store receipt data for sharing
      window.currentReceipt = {
        reference: transfer.reference,
        date: now.toISOString(),
        from: acc.account_name + ' · ' + acc.account_number,
        to: state.recipient.name,
        bank: state.recipient.bank,
        account: state.recipient.account,
        amount: amount,
        currency: acc.currency,
        fee: 0,
        total: amount,
        desc: desc || '—'
      };
      
      showStep(4);
      UI.toast('Transfer completed successfully.', 'success');
      
      // Refresh balance in dashboard if available
      if (window.AppShell && window.AppShell.refreshBalance) {
        window.AppShell.refreshBalance();
      }
    } catch (e) {
      btn.disabled = false;
      btn.textContent = 'Confirm & Send';
      if (e && e.message !== 'CANCELLED') UI.toast(UI.apiErrorMessage(e), 'error');
    }
  });

  document.getElementById('step3-back').addEventListener('click', function () { showStep(2); });

  // Generate standalone receipt image (off-screen rendering)
  function generateReceiptImage(receipt) {
    return new Promise(async (resolve, reject) => {
      try {
        // Create a clean, isolated receipt container
        const container = document.createElement('div');
        container.className = 'receipt-card';
        container.style.cssText = `
          position: fixed;
          left: -9999px;
          top: -9999px;
          width: 360px;
          background: #fff;
          border-radius: 16px;
          box-shadow: 0 4px 24px rgba(0,0,0,0.08);
          border: 1px solid #e3e8f0;
          font-family: "Plus Jakarta Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          overflow: hidden;
        `;

        // Build receipt HTML
        const primarySymbol = receipt.currency === 'EUR' ? '€' : receipt.currency === 'USD' ? '$' : receipt.currency;
        const secondarySymbol = receipt.currency === 'EUR' ? '$' : '€';
        const eurToUsd = 1.08;
        const usdAmount = receipt.amount * (receipt.currency === 'EUR' ? eurToUsd : 1/eurToUsd);

        container.innerHTML = `
          <div class="receipt-header" style="display:flex;align-items:center;justify-content:space-between;padding:16px 16px 12px;background:linear-gradient(135deg,#1a7f3d 0%,#0d501f 100%);color:#fff;">
            <div class="receipt-brand" style="display:flex;align-items:center;gap:10px;">
              <div class="receipt-logo" style="width:36px;height:36px;border-radius:8px;background:rgba(255,255,255,0.15);padding:6px;display:flex;align-items:center;justify-content:center;">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;stroke:#fff;"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>
              </div>
              <div>
                <strong style="font-size:15px;color:#fff;">Sagroeurope</strong>
                <span style="font-size:11px;color:rgba(255,255,255,0.8);">Agricultural Banking & Financial Services</span>
              </div>
            </div>
            <div class="receipt-status completed" style="display:flex;align-items:center;gap:6px;padding:6px 14px;background:rgba(255,255,255,0.15);color:#fff;border-radius:999px;font-size:12px;font-weight:700;backdrop-filter:blur(10px);border:1px solid rgba(255,255,255,0.2);">
              <strong>Completed</strong>
            </div>
          </div>

          <div class="receipt-meta" style="padding:14px 16px;background:#fff;">
            <div class="meta-row" style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #e3e8f0;">
              <span class="meta-label" style="font-size:11px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.03em;">Ref</span>
              <span class="meta-value" style="font-size:13px;color:#16233a;font-weight:500;text-align:right;word-break:break-word;">${UI.escapeHtml(receipt.reference)}</span>
            </div>
            <div class="meta-row" style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #e3e8f0;">
              <span class="meta-label" style="font-size:11px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.03em;">Date & Time</span>
              <span class="meta-value" style="font-size:13px;color:#16233a;font-weight:500;text-align:right;word-break:break-word;">${UI.formatDateTime(receipt.date)}</span>
            </div>
            <div class="meta-row" style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;">
              <span class="meta-label" style="font-size:11px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.03em;">Status</span>
              <span class="meta-value" style="font-size:13px;color:#16233a;font-weight:500;text-align:right;word-break:break-word;"><span class="badge badge-completed" style="background:#e6f6ed;color:#1a9e5a;display:inline-flex;align-items:center;gap:5px;padding:3px 10px;border-radius:999px;font-size:10px;font-weight:600;line-height:1.5;white-space:nowrap;">Completed</span></span>
            </div>
          </div>

          <div style="height:1px;background:linear-gradient(90deg,transparent,#e3e8f0,transparent);margin:0 16px;"></div>

          <div class="receipt-party-section" style="display:grid;grid-template-columns:1fr 1fr;gap:0;padding:16px;background:#f8fafd;border-top:1px solid #e3e8f0;border-bottom:1px solid #e3e8f0;">
            <div class="party-card from" style="padding:12px 8px;">
              <div class="party-header" style="margin-bottom:8px;">
                <span class="party-tag" style="font-size:10px;color:#7c8aa0;font-weight:700;text-transform:uppercase;letter-spacing:.05em;">From</span>
              </div>
              <div class="party-details">
                <div class="party-name" style="font-size:13px;font-weight:700;color:#16233a;margin-bottom:4px;">${UI.escapeHtml(receipt.from)}</div>
                <div class="party-account" style="font-size:11px;font-weight:600;color:#16233a;font-family:ui-monospace,monospace;">${UI.escapeHtml(receipt.fromAccount || receipt.account)}</div>
              </div>
            </div>
            <div class="party-divider" style="width:1px;background:#e3e8f0;margin:0 12px;align-self:stretch;"></div>
            <div class="party-card to" style="padding:12px 8px;">
              <div class="party-header" style="margin-bottom:8px;">
                <span class="party-tag" style="font-size:10px;color:#7c8aa0;font-weight:700;text-transform:uppercase;letter-spacing:.05em;">To</span>
              </div>
              <div class="party-details">
                <div class="party-name" style="font-size:13px;font-weight:700;color:#16233a;margin-bottom:4px;">${UI.escapeHtml(receipt.to)}</div>
                <div class="party-bank" style="font-size:11px;color:#7c8aa0;margin-bottom:2px;">${UI.escapeHtml(receipt.bank)}</div>
                <div class="party-account" style="font-size:11px;font-weight:600;color:#16233a;font-family:ui-monospace,monospace;">${UI.escapeHtml(receipt.account)}</div>
              </div>
            </div>
          </div>

          <div style="height:1px;background:linear-gradient(90deg,transparent,#e3e8f0,transparent);margin:0 16px;"></div>

          <div class="receipt-amount-card" style="padding:16px;background:linear-gradient(135deg,#e6f4ea 0%,#fff 100%);border-top:1px solid #e3e8f0;">
            <div class="amount-row" style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;">
              <div class="amount-col" style="padding:12px;background:#fff;border-radius:10px;border:1px solid #e3e8f0;text-align:center;">
                <span class="amount-label" style="display:block;font-size:10px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:6px;">Amount</span>
                <div class="amount-value" style="font-size:16px;font-weight:800;color:#16233a;letter-spacing:-0.01em;">${primarySymbol}${receipt.amount.toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}</div>
              </div>
              <div class="amount-col" style="padding:12px;background:#fff;border-radius:10px;border:1px solid #e3e8f0;text-align:center;">
                <span class="amount-label" style="display:block;font-size:10px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:6px;">Fee</span>
                <div class="amount-value fee" style="font-size:16px;font-weight:800;color:#d64045;letter-spacing:-0.01em;">${primarySymbol}${receipt.fee.toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}</div>
              </div>
              <div class="amount-col total" style="padding:12px;background:linear-gradient(135deg,#e6f4ea 0%,#1a7f3d 100%);border-color:#1a7f3d;border-radius:10px;border:1px solid #1a7f3d;text-align:center;">
                <span class="amount-label" style="display:block;font-size:10px;color:rgba(255,255,255,0.7);font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:6px;">Total</span>
                <div class="amount-value" style="font-size:20px;font-weight:800;color:#fff;letter-spacing:-0.01em;">${primarySymbol}${(receipt.amount + receipt.fee).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}</div>
              </div>
            </div>
          </div>

          <div style="height:1px;background:linear-gradient(90deg,transparent,#e3e8f0,transparent);margin:0 16px;"></div>

          <div class="receipt-meta" style="padding:14px 16px;background:#fff;">
            <div class="meta-row" style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;">
              <span class="meta-label" style="font-size:11px;color:#7c8aa0;font-weight:600;text-transform:uppercase;letter-spacing:.03em;">Description</span>
              <span class="meta-value" style="font-size:13px;color:#16233a;font-weight:500;text-align:right;word-break:break-word;">${UI.escapeHtml(receipt.desc)}</span>
            </div>
          </div>

          <div style="padding:16px;background:#fff;border-top:1px solid #e3e8f0;">
            <p style="font-size:10px;color:#7c8aa0;margin-bottom:16px;line-height:1.5;text-align:center;">This receipt confirms the transfer was completed. Funds debited from your account.</p>
          </div>
        `;

        // Add to body and render
        document.body.appendChild(container);

        // Wait for layout
        await new Promise(r => requestAnimationFrame(r));

        // Capture with html2canvas
        const canvas = await html2canvas(container, {
          scale: 3,
          useCORS: true,
          logging: false,
          backgroundColor: '#ffffff',
          width: container.scrollWidth,
          height: container.scrollHeight,
          windowWidth: container.scrollWidth,
          windowHeight: container.scrollHeight,
        });

        // Clean up
        document.body.removeChild(container);

        // Convert to blob
        const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png', 0.95));
        resolve(blob);
      } catch (e) {
        reject(e);
      }
    });
  }

  // Share receipt as image
  window.shareReceipt = async function () {
    const receipt = window.currentReceipt;
    if (!receipt) return;

    try {
      UI.toast('Generating receipt image...', 'info');

      // Generate standalone receipt image
      const blob = await generateReceiptImage(receipt);

      // Prepare file for sharing
      const file = new File([blob], `receipt-${receipt.reference}.png`, { type: 'image/png' });

      const shareData = {
        title: 'Sagroeurope Transfer Receipt',
        text: `Transfer Completed - ${receipt.reference}`,
        files: [file]
      };

      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share(shareData);
        UI.toast('Receipt shared successfully!', 'success');
      } else if (navigator.share) {
        // Fallback: share without file if files not supported
        await navigator.share({
          title: 'Sagroeurope Transfer Receipt',
          text: `Transfer Completed - ${receipt.reference}\n\nAmount: ${UI.money(receipt.amount, receipt.currency)}\nTo: ${receipt.to}\nDate: ${UI.formatDateTime(receipt.date)}\nReference: ${receipt.reference}`,
          url: window.location.href
        });
      } else {
        // Fallback: download the image
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `receipt-${receipt.reference}.png`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        UI.toast('Receipt image downloaded', 'success');
      }
    } catch (e) {
      console.error('Share error:', e);
      if (e.name !== 'AbortError') {
        UI.toast('Unable to share receipt', 'warning');
      }
    }
  };

  await load();
  PageLoader.hide();
})();