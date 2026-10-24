Cypress.on('uncaught:exception', () => false)

// Da más tiempo de espera global para Flutter web
Cypress.config('defaultCommandTimeout', 15000)
Cypress.config('pageLoadTimeout', 30000)