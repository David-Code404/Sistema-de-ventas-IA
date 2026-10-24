// HU-17 | Tarea 960 — Testear acceso al sistema con roles (caja negra)
// Usuarios: admin/admin123  cajero/cajero123  cliente/cliente123
// Usa flt-semantics (árbol de accesibilidad de Flutter web CanvasKit)

const API     = 'http://localhost:8000'
const APP_URL = 'http://localhost:60125'   // ajusta si tu puerto es diferente

// ── Activa el árbol semántico de Flutter (necesario en CanvasKit) ──
const activarSemantica = () => {
  cy.get('body').trigger('keydown', {
    key: 'Tab', keyCode: 9, which: 9, bubbles: true,
  })
  cy.wait(600)
}

// ── Encuentra texto dentro del árbol semántico de Flutter ──────────
const flutterContains = (patron) =>
  cy.get('flt-semantics', { timeout: 12000 })
    .filter(`:contains("${typeof patron === 'string' ? patron : ''}")`)

// Versión con regex — busca en todos los flt-semantics
const flutterContainsRe = (regex) =>
  cy.get('flt-semantics', { timeout: 12000 }).then(($els) => {
    const found = [...$els].some((el) => regex.test(el.textContent || el.getAttribute('aria-label') || ''))
    expect(found, `Esperaba encontrar: ${regex}`).to.be.true
  })

const flutterNotContainsRe = (regex) =>
  cy.get('flt-semantics', { timeout: 12000 }).then(($els) => {
    const found = [...$els].some((el) => regex.test(el.textContent || el.getAttribute('aria-label') || ''))
    expect(found, `NO debería existir: ${regex}`).to.be.false
  })

// ── Login ──────────────────────────────────────────────────────────
const login = (username, password) => {
  cy.visit(APP_URL)
  cy.wait(2000)
  activarSemantica()

  // Flutter renderiza <input> reales para campos de texto
  cy.get('input').eq(0).clear({ force: true }).type(username, { force: true })
  cy.get('input').eq(1).clear({ force: true }).type(password,  { force: true })

  // Clic en botón Iniciar sesión (flt-semantics con ese texto)
  cy.get('flt-semantics[aria-label]').then(($els) => {
    const btn = [...$els].find((el) =>
      /iniciar\s+sesi[oó]n/i.test(el.getAttribute('aria-label') || el.textContent || '')
    )
    if (btn) {
      cy.wrap(btn).click({ force: true })
    } else {
      // Fallback: Enter en el campo de contraseña
      cy.get('input').eq(1).type('{enter}', { force: true })
    }
  })

  cy.wait(2500)
  activarSemantica()
}

// ── Logout ─────────────────────────────────────────────────────────
const logout = () => {
  cy.get('flt-semantics[aria-label]', { timeout: 8000 }).then(($els) => {
    const btn = [...$els].find((el) =>
      /cerrar\s+sesi[oó]n/i.test(el.getAttribute('aria-label') || el.textContent || '')
    )
    if (btn) cy.wrap(btn).click({ force: true })
  })
  cy.wait(1000)
}

// ══════════════════════════════════════════════════════════════════
describe('HU-17 · Acceso por roles', () => {

  // ── ADMINISTRADOR ─────────────────────────────────────────────
  describe('Rol: Administrador', () => {

    before(() => login('admin', 'admin123'))
    after(() => logout())

    it('Ve Dashboard en el sidebar', () => {
      flutterContainsRe(/dashboard/i)
    })

    it('Ve Inventario en el sidebar', () => {
      flutterContainsRe(/inventario/i)
    })

    it('Ve Categorías en el sidebar', () => {
      flutterContainsRe(/categor[ií]as/i)
    })

    it('NO ve botón Nueva venta', () => {
      flutterNotContainsRe(/nueva\s+venta/i)
    })

    it('El endpoint /dashboard/estadisticas responde 200', () => {
      cy.request(`${API}/dashboard/estadisticas?dias=30`)
        .its('status').should('eq', 200)
    })
  })

  // ── CAJERO ────────────────────────────────────────────────────
  describe('Rol: Cajero', () => {

    before(() => login('cajero', 'cajero123'))
    after(() => logout())

    it('Ve la sección Ventas en el sidebar', () => {
      flutterContainsRe(/ventas/i)
    })

    it('Ve el botón Nueva venta', () => {
      flutterContainsRe(/nueva\s+venta/i)
    })

    it('NO ve Dashboard en el sidebar', () => {
      flutterNotContainsRe(/dashboard/i)
    })

    it('El endpoint /ventas responde 200 (sin error de cajero)', () => {
      cy.request(`${API}/ventas?limite=10`)
        .its('status').should('eq', 200)
    })
  })

  // ── CLIENTE ───────────────────────────────────────────────────
  describe('Rol: Cliente', () => {

    before(() => login('cliente', 'cliente123'))
    after(() => logout())

    it('Ve el Catálogo en pantalla', () => {
      flutterContainsRe(/cat[áa]logo/i)
    })

    it('NO ve Dashboard', () => {
      flutterNotContainsRe(/dashboard/i)
    })

    it('NO ve Inventario', () => {
      flutterNotContainsRe(/inventario/i)
    })

    it('NO ve Nueva venta', () => {
      flutterNotContainsRe(/nueva\s+venta/i)
    })
  })

  // ── SEGURIDAD — API directa ────────────────────────────────────
  describe('Acceso no autorizado', () => {

    it('Login con contraseña incorrecta devuelve 401', () => {
      cy.request({
        method: 'POST',
        url: `${API}/auth/login`,
        body: { username: 'admin', password: 'incorrecta' },
        failOnStatusCode: false,
      }).its('status').should('eq', 401)
    })

    it('Login con usuario inexistente devuelve 401', () => {
      cy.request({
        method: 'POST',
        url: `${API}/auth/login`,
        body: { username: 'noexiste', password: '1234' },
        failOnStatusCode: false,
      }).its('status').should('eq', 401)
    })
  })
})