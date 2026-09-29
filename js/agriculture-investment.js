// Sagroeurope — Agriculture Investment module
(async function () {
  await AppShell.init({ title: 'Agriculture Investment' });
  const user = Auth.user;

  // Investment opportunities data
  const opportunities = [
    {
      id: 'crop-production',
      title: 'Crop Production & Development',
      subtitle: 'Cross-border crop cultivation programs',
      description: 'Invest in large-scale crop production across Europe and Africa. Programs include wheat, corn, soybeans, and specialty crops with guaranteed offtake agreements.',
      icon: '🌾',
      category: 'Crop Production',
      minInvestment: 1000,
      maxInvestment: 500000,
      duration: '12 months',
      riskLevel: 'Medium',
      regions: ['Spain', 'France', 'Ukraine', 'Nigeria', 'Kenya']
    },
    {
      id: 'livestock-farming',
      title: 'Animal Farming & Livestock Development',
      subtitle: 'Sustainable livestock and dairy operations',
      description: 'Modern cattle, poultry, and dairy farming with automated feeding systems and veterinary care. High demand for protein products in European markets.',
      icon: '🐄',
      category: 'Livestock',
      minInvestment: 2000,
      maxInvestment: 750000,
      duration: '18 months',
      riskLevel: 'Medium-High',
      regions: ['Germany', 'Poland', 'Romania', 'South Africa', 'Ethiopia']
    },
    {
      id: 'food-production',
      title: 'Food Production & Security',
      subtitle: 'Agro-processing and food security initiatives',
      description: 'Invest in food processing facilities, cold chain logistics, and strategic grain reserves. Government-backed programs ensuring food security across regions.',
      icon: '🍞',
      category: 'Food Security',
      minInvestment: 5000,
      maxInvestment: 1000000,
      duration: '24 months',
      riskLevel: 'Low-Medium',
      regions: ['Netherlands', 'Italy', 'Ghana', 'Morocco', 'Egypt']
    }
  ];

  let investmentBalance = 0;
  let investments = [];

  async function loadData() {
    try {
      // Load user's investment balance and investments from database
      // For now, we'll simulate with localStorage until backend tables are created
      const saved = localStorage.getItem('agri_investments_' + user.id);
      if (saved) {
        investments = JSON.parse(saved);
        investmentBalance = investments.reduce((sum, inv) => sum + inv.amount, 0);
      }
      
      renderBalance();
      renderOpportunities();
      renderMyInvestments();
      renderReturnsHistory();
    } catch (e) {
      console.error('Failed to load agriculture investment data:', e);
      UI.toast('Failed to load investment data', 'error');
    }
  }

  function renderBalance() {
    const primaryCurrency = APP_CONFIG.primaryCurrency || 'EUR';
    const secondaryCurrency = APP_CONFIG.secondaryCurrency || 'USD';
    const primarySymbol = APP_CONFIG.currencySymbols[primaryCurrency] || '€';
    const secondarySymbol = APP_CONFIG.currencySymbols[secondaryCurrency] || '$';
    
    // Simple EUR to USD conversion (in production, use real-time rate)
    const eurToUsd = 1.08;
    const usdAmount = investmentBalance * eurToUsd;
    const projectedAnnual = investmentBalance * 0.78;
    const projectedUsd = projectedAnnual * eurToUsd;

    document.getElementById('investment-total-balance').textContent = 
      primarySymbol + investmentBalance.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    document.getElementById('investment-total-usd').textContent = 
      secondarySymbol + usdAmount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    document.getElementById('investment-projected').textContent = 
      `Projected: ${primarySymbol}${projectedAnnual.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} / ${secondarySymbol}${projectedUsd.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} per year`;
  }

  function renderOpportunities() {
    const el = document.getElementById('investment-opportunities');
    el.innerHTML = opportunities.map(function (opp) {
      return `
        <div class="investment-card" data-id="${opp.id}">
          <div class="investment-card-header">
            <div class="investment-icon">${opp.icon}</div>
            <div class="investment-category">${opp.category}</div>
            <span class="badge badge-success">78% Annual Return</span>
          </div>
          <h3 class="investment-title">${opp.title}</h3>
          <p class="investment-subtitle">${opp.subtitle}</p>
          <p class="investment-desc">${opp.description}</p>
          <div class="investment-details">
            <div class="investment-detail">
              <span class="detail-label">Min Investment</span>
              <span class="detail-value">€${opp.minInvestment.toLocaleString()}</span>
            </div>
            <div class="investment-detail">
              <span class="detail-label">Max Investment</span>
              <span class="detail-value">€${opp.maxInvestment.toLocaleString()}</span>
            </div>
            <div class="investment-detail">
              <span class="detail-label">Duration</span>
              <span class="detail-value">${opp.duration}</span>
            </div>
            <div class="investment-detail">
              <span class="detail-label">Risk Level</span>
              <span class="detail-value">${opp.riskLevel}</span>
            </div>
          </div>
          <div class="investment-regions">
            <span class="regions-label">Available in:</span>
            ${opp.regions.map(r => `<span class="region-tag">${r}</span>`).join('')}
          </div>
          <button class="btn btn-primary invest-btn" data-id="${opp.id}" style="width:100%;margin-top:16px">Invest Now</button>
        </div>
      `;
    }).join('');

    // Add event listeners for invest buttons
    el.querySelectorAll('.invest-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        const oppId = this.getAttribute('data-id');
        const opp = opportunities.find(o => o.id === oppId);
        showInvestModal(opp);
      });
    });
  }

  function showInvestModal(opp) {
    const modal = UI.openModal(`
      <div class="invest-modal">
        <div class="invest-modal-header">
          <div class="invest-modal-icon">${opp.icon}</div>
          <div>
            <h3 style="margin:0">${opp.title}</h3>
            <p class="text-sm text-muted" style="margin:4px 0 0">${opp.subtitle}</p>
          </div>
        </div>
        <p style="color:var(--text-2);margin-bottom:20px">${opp.description}</p>
        
        <div class="invest-modal-details">
          <div class="detail-row"><span>Min Investment</span><strong>€${opp.minInvestment.toLocaleString()}</strong></div>
          <div class="detail-row"><span>Max Investment</span><strong>€${opp.maxInvestment.toLocaleString()}</strong></div>
          <div class="detail-row"><span>Duration</span><strong>${opp.duration}</strong></div>
          <div class="detail-row"><span>Expected Return</span><strong>78% Annual</strong></div>
          <div class="detail-row"><span>Risk Level</span><strong>${opp.riskLevel}</strong></div>
        </div>
        
        <div class="field">
          <label>Investment Amount (EUR)</label>
          <div class="amount-field">
            <input type="number" class="input" id="invest-amount" min="${opp.minInvestment}" max="${opp.maxInvestment}" step="100" placeholder="Enter amount">
            <span class="currency-tag">€</span>
          </div>
          <div class="form-error" id="invest-error"></div>
        </div>
        
        <div class="invest-summary">
          <div class="summary-row"><span>Investment</span><span id="invest-display">€0.00</span></div>
          <div class="summary-row"><span>Projected Annual Return (78%)</span><span id="return-display">€0.00</span></div>
          <div class="summary-row total"><span>Total After 1 Year</span><span id="total-display">€0.00</span></div>
        </div>
      </div>
    `, {
      title: 'Invest in ' + opp.title,
      footer: '<button class="btn btn-outline" data-cancel>Cancel</button><button class="btn btn-primary" data-invest>Confirm Investment</button>'
    });

    const amountInput = modal.body.querySelector('#invest-amount');
    const errorEl = modal.body.querySelector('#invest-error');
    const investDisplay = modal.body.querySelector('#invest-display');
    const returnDisplay = modal.body.querySelector('#return-display');
    const totalDisplay = modal.body.querySelector('#total-display');

    function updateDisplay() {
      const amount = Math.max(opp.minInvestment, Math.min(opp.maxInvestment, Number(amountInput.value) || 0));
      const annualReturn = amount * 0.78;
      const total = amount + annualReturn;
      investDisplay.textContent = '€' + amount.toLocaleString('en-US', { minimumFractionDigits: 2 });
      returnDisplay.textContent = '€' + annualReturn.toLocaleString('en-US', { minimumFractionDigits: 2 });
      totalDisplay.textContent = '€' + total.toLocaleString('en-US', { minimumFractionDigits: 2 });
    }

    amountInput.addEventListener('input', updateDisplay);
    updateDisplay();

    modal.footer.querySelector('[data-cancel]').addEventListener('click', modal.close);
    modal.footer.querySelector('[data-invest]').addEventListener('click', async function () {
      const amount = Number(amountInput.value) || 0;
      if (amount < opp.minInvestment || amount > opp.maxInvestment) {
        errorEl.textContent = `Amount must be between €${opp.minInvestment.toLocaleString()} and €${opp.maxInvestment.toLocaleString()}`;
        return;
      }
      
      const btn = this;
      btn.disabled = true;
      btn.textContent = 'Processing...';
      
      try {
        // In production, this would call an RPC to create the investment
        // For now, save to localStorage
        const newInvestment = {
          id: 'inv_' + Date.now(),
          opportunityId: opp.id,
          title: opp.title,
          category: opp.category,
          amount: amount,
          currency: 'EUR',
          annualReturnRate: 0.78,
          startDate: new Date().toISOString(),
          duration: opp.duration,
          status: 'active',
          projectedAnnualReturn: amount * 0.78
        };
        
        investments.push(newInvestment);
        investmentBalance += amount;
        localStorage.setItem('agri_investments_' + user.id, JSON.stringify(investments));
        
        // Create a transaction record
        await UI.rpc('create_customer_deposit', {
          p_user_id: user.id,
          p_account_id: (await getDefaultEurAccount()),
          p_amount: amount,
          p_currency: 'EUR',
          p_method: 'agriculture_investment',
          p_note: `Agriculture Investment: ${opp.title}`,
          p_pin: await getInvestmentPin()
        }).catch(() => {}); // Ignore if function doesn't exist yet
        
        UI.toast('Investment confirmed! €' + amount.toLocaleString() + ' invested in ' + opp.title, 'success');
        modal.close();
        renderBalance();
        renderMyInvestments();
        renderReturnsHistory();
      } catch (e) {
        errorEl.textContent = UI.apiErrorMessage(e);
        btn.disabled = false;
        btn.textContent = 'Confirm Investment';
      }
    });
  }

  async function getDefaultEurAccount() {
    const { data } = await SB.from('accounts').select('id').eq('user_id', user.id).eq('currency', 'EUR').eq('status', 'active').limit(1);
    return data && data[0] ? data[0].id : null;
  }

  async function getInvestmentPin() {
    return new Promise((resolve, reject) => {
      const pinModal = UI.openModal(`
        <div class="pin-modal">
          <div class="pin-icon">🔒</div>
          <p class="pin-desc" style="font-weight:600;color:var(--text);margin-bottom:4px">Confirm Investment</p>
          <p class="pin-desc">Enter your 4-digit security PIN to authorize this investment.</p>
          ${UI.pinBoxesHTML('invest-pin-boxes')}
          <div class="form-error pin-error" id="invest-pin-error"></div>
        </div>
      `, { title: 'Confirm Investment', footer: '<button class="btn btn-outline" data-cancel>Cancel</button>', dismissable: false });
      
      const controller = UI.mountPinInput(modal.body.querySelector('.pin-inputs'), {
        onComplete: async function (pin) {
          const errEl = modal.body.querySelector('#invest-pin-error');
          try {
            const res = await UI.verifyCustomerPin(pin);
            if (res.ok) {
              modal.close();
              resolve(pin);
            } else {
              controller.clear();
              errEl.textContent = res.message || 'Incorrect PIN.';
            }
          } catch (e) {
            controller.clear();
            errEl.textContent = UI.apiErrorMessage(e);
          }
        }
      });
      modal.footer.querySelector('[data-cancel]').addEventListener('click', function () {
        modal.close();
        reject(new Error('CANCELLED'));
      });
      controller.focusFirst();
    });
  }

  function renderMyInvestments() {
    const el = document.getElementById('my-investments');
    if (!investments.length) {
      el.innerHTML = `
        <div class="empty-state" style="padding:40px 20px">
          <div class="empty-icon">🌱</div>
          <h3>No investments yet</h3>
          <p class="text-muted">Start investing in agriculture opportunities above</p>
        </div>
      `;
      return;
    }
    
    el.innerHTML = '<div class="investment-list">' + investments.map(function (inv) {
      const startDate = new Date(inv.startDate);
      const monthsElapsed = (Date.now() - startDate.getTime()) / (1000 * 60 * 60 * 24 * 30);
      const currentReturn = inv.amount * inv.annualReturnRate * (monthsElapsed / 12);
      const totalValue = inv.amount + currentReturn;
      
      return `
        <div class="investment-item">
          <div class="investment-item-header">
            <div class="investment-item-icon">${getCategoryIcon(inv.category)}</div>
            <div>
              <strong>${inv.title}</strong>
              <div class="text-sm text-muted">${inv.category} · ${formatDuration(inv.duration)}</div>
            </div>
          </div>
          <div class="investment-item-stats">
            <div class="stat">
              <span class="stat-label">Invested</span>
              <span class="stat-value">${UI.money(inv.amount, inv.currency)}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Current Value</span>
              <span class="stat-value text-success">${UI.money(totalValue, inv.currency)}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Returns</span>
              <span class="stat-value text-success">+${UI.money(currentReturn, inv.currency)}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Annual Rate</span>
              <span class="stat-value">${(inv.annualReturnRate * 100).toFixed(0)}%</span>
            </div>
          </div>
          <div class="investment-progress">
            <div class="progress-bar">
              <div class="progress-fill" style="width:${Math.min(100, (monthsElapsed / parseDuration(inv.duration)) * 100)}%"></div>
            </div>
            <span class="progress-text">${Math.min(100, Math.round((monthsElapsed / parseDuration(inv.duration)) * 100))}% complete</span>
          </div>
        </div>
      `;
    }).join('') + '</div>';
  }

  function renderReturnsHistory() {
    const el = document.getElementById('returns-history');
    if (!investments.length) {
      el.innerHTML = UI.emptyState('No returns history yet. Returns will appear as your investments grow.');
      return;
    }
    
    // Generate monthly return entries for each investment
    const allReturns = [];
    investments.forEach(function (inv) {
      const startDate = new Date(inv.startDate);
      const now = new Date();
      const monthsElapsed = Math.max(1, Math.floor((now - startDate) / (1000 * 60 * 60 * 24 * 30)));
      
      for (let m = 1; m <= monthsElapsed; m++) {
        const date = new Date(startDate.getFullYear(), startDate.getMonth() + m, 1);
        const monthlyReturn = inv.amount * (inv.annualReturnRate / 12);
        allReturns.push({
          date: date,
          investment: inv.title,
          category: inv.category,
          amount: monthlyReturn,
          currency: inv.currency
        });
      }
    });
    
    // Sort by date descending
    allReturns.sort((a, b) => b.date - a.date);
    
    if (!allReturns.length) {
      el.innerHTML = UI.emptyState('Returns will appear monthly as your investments mature.');
      return;
    }
    
    el.innerHTML = '<div class="tx-list">' + allReturns.slice(0, 20).map(function (r) {
      return `
        <div class="tx-item">
          <div class="tx-icon" style="background:var(--success-soft);color:var(--success)">${getCategoryIcon(r.category)}</div>
          <div class="tx-info">
            <div class="tx-title">${r.investment}</div>
            <div class="tx-sub">${UI.formatDate(r.date)} · Monthly return from ${r.category}</div>
          </div>
          <div class="tx-amount text-success">+${UI.money(r.amount, r.currency)}</div>
        </div>
      `;
    }).join('') + '</div>';
  }

  function getCategoryIcon(category) {
    const icons = { 'Crop Production': '🌾', 'Livestock': '🐄', 'Food Security': '🍞' };
    return icons[category] || '🌱';
  }

  function formatDuration(duration) {
    return duration;
  }

  function parseDuration(duration) {
    const match = duration.match(/(\d+)/);
    return match ? parseInt(match[1]) : 12;
  }

  // Event listener for invest now button
  document.getElementById('invest-btn')?.addEventListener('click', function (e) {
    e.preventDefault();
    document.getElementById('investment-opportunities').scrollIntoView({ behavior: 'smooth' });
  });

  await loadData();
  PageLoader.hide();
})();