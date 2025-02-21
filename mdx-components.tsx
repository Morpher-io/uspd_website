// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-nocheck

import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs'

const {
  ...docsComponents
} = getDocsMDXComponents()

export const useMDXComponents: typeof getDocsMDXComponents = components => ({
  ...docsComponents,
  ...components
})