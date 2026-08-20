// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// The pages under src/content/docs/ ARE the reference — this site is the source of truth.
// There is no longer a single-file copy in ../docs/.
export default defineConfig({
	// Deployed to GitHub Pages as a project site, so everything is served under
	// /oxi-e16-lua-api/. Absolute links written in Markdown are NOT base-prefixed
	// automatically — they must include the base themselves. See CLAUDE.md.
	site: 'https://tsln-lab.github.io',
	base: '/oxi-e16-lua-api',
	integrations: [
		starlight({
			title: 'OXI E16 Lua API',
			description:
				'Firmware API reference for OXI E16 Lua scripts, transcribed from the official manual and corrected against hardware.',
			tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
			credits: false,
			sidebar: [
				{
					label: 'Writing scripts',
					items: [
						{ label: 'Overview', slug: '' },
						{ label: 'Execution model', slug: 'execution-model' },
						{ label: 'Assignments', slug: 'assignments' },
						{ label: 'Global objects', slug: 'globals' },
						{ label: 'Callbacks', slug: 'callbacks' },
					],
				},
				{
					label: 'API reference',
					items: [
						{ label: 'controller', slug: 'api/controller' },
						{ label: 'midi', slug: 'api/midi' },
						{ label: 'leds', slug: 'api/leds' },
						{ label: 'slots', slug: 'api/slots' },
						{ label: 'var', slug: 'api/var' },
						{ label: 'page', slug: 'api/page' },
						{ label: 'system', slug: 'api/system' },
					],
				},
				{
					label: 'In practice',
					items: [
						{ label: 'Gotchas', slug: 'gotchas' },
						{ label: 'Patterns', slug: 'patterns' },
						{ label: 'Device context', slug: 'device-context' },
						{ label: 'Example: TX81Z editor', slug: 'example-tx81z' },
						{ label: 'Ableton Live', slug: 'ableton-live' },
						{ label: 'Open questions', slug: 'open-questions' },
					],
				},
			],
		}),
	],
});
