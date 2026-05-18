import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Vite config: in dev, proxy API calls to the local ASP.NET app so the SPA
// can call relative URLs like `/customers` and `/projects`.
// VITE_DEV_API_PROXY allows overriding the target (e.g. "http://naas:8000"
// when running inside docker compose). Defaults to localhost:8000.
const proxyTarget = process.env.VITE_DEV_API_PROXY ?? 'http://localhost:8000'

export default defineConfig({
	plugins: [react()],
	server: {
		port: 5173,
		proxy: {
			'/auth': proxyTarget,
			'/customers': proxyTarget,
			'/projects': proxyTarget,
			'/upload': proxyTarget,
			'/reject': proxyTarget,
			'/openapi': proxyTarget
		}
	},
	build: {
		outDir: 'dist',
		sourcemap: true
	}
})
