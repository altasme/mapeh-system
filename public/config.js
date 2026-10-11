// Public values only. Never put the service-role key, a database password or a user password here.
window.APP_CONFIG = {
  environment: "test",                         // "test" shows the banner; "production" hides it
  supabaseUrl: "https://[PROJECT-REF].supabase.co",
  supabasePublishableKey: "[PUBLISHABLE_KEY]", // public by design; security comes from RLS
  authEmailDomain: "users.mapehdavnor.altasme.app",
  supabaseJsVersion: "2.117.3",                // pinned in index.html with SRI
  features: {                                  // RESERVED upgrade seams. Do not wire.
    recordEditing: false,
    excelDataExport: false,
    importValidation: false,
    duplicateDetection: false,
    selfServicePassword: false
  }
};
