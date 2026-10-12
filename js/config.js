// Sagroeurope — Client configuration
// Replace these values with your Supabase project credentials.
// ONLY the public anon key belongs here. Never expose the service_role key.
const APP_CONFIG = {
  supabaseUrl: 'https://vefynvjddevizlbqiekd.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZlZnludmpkZGV2aXpsYnFpZWtkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MTAzODYsImV4cCI6MjEwNzM4NjM4Nn0.yD_HhDcyVfYhLfQrCvMPx6MtQNBA5kzUTBrtmnsr4e0',
  bankName: 'Sagroeurope',
  primaryCurrency: 'EUR',
  secondaryCurrency: 'USD',
  supportedCurrencies: ['EUR', 'USD', 'GBP', 'NGN', 'CAD', 'AUD', 'CHF', 'JPY', 'CNY', 'ZAR'],
  currencySymbols: {
    EUR: '€',
    USD: '$',
    GBP: '£',
    NGN: '₦',
    CAD: 'C$',
    AUD: 'A$',
    CHF: 'CHF',
    JPY: '¥',
    CNY: '¥',
    ZAR: 'R'
  },
  pageSize: 10,
  btcPriceApi: 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd'
};
