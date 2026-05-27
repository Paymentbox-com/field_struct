import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'en-US',
  title: 'FieldStruct',
  description: 'Typed POROs with declared attributes, coercion, and validation.',

  // Built and deployed to https://paymentbox-com.github.io/field_struct/
  base: '/field_struct/',

  cleanUrls: true,
  lastUpdated: true,

  head: [
    ['meta', { name: 'theme-color', content: '#0f766e' }]
  ],

  themeConfig: {
    siteTitle: 'FieldStruct',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Changelog', link: 'https://github.com/Paymentbox-com/field_struct/blob/main/CHANGELOG.md' },
      { text: 'RubyGems', link: 'https://rubygems.org/gems/field_struct' }
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Defining Fields', link: '/guide/defining-fields' }
          ]
        },
        {
          text: 'The Type System',
          items: [
            { text: 'Types & Coercion', link: '/guide/types-and-coercion' },
            { text: 'Custom Types & Registries', link: '/guide/custom-types' },
            { text: 'Field Options', link: '/guide/field-options' }
          ]
        },
        {
          text: 'Validation & Composition',
          items: [
            { text: 'Validation', link: '/guide/validation' },
            { text: 'Nested & Union Types', link: '/guide/nested-and-union' },
            { text: 'Pattern Matching', link: '/guide/pattern-matching' }
          ]
        },
        {
          text: 'Class-level Behavior',
          items: [
            { text: 'Class Macros', link: '/guide/class-macros' },
            { text: 'Serialization', link: '/guide/serialization' }
          ]
        }
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/Paymentbox-com/field_struct' }
    ],

    editLink: {
      pattern: 'https://github.com/Paymentbox-com/field_struct/edit/main/site/:path',
      text: 'Edit this page on GitHub'
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2026 Paymentbox'
    },

    search: {
      provider: 'local'
    }
  }
})
