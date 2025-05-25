<script setup>
import DefaultTheme from 'vitepress/theme'
import Sponsors from "./Sponsors.vue"
import { useData } from 'vitepress'

const { theme } = useData()
const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #aside-ads-before>
      <Sponsors v-if="theme.sponsors.enabled" :sponsors="theme.sponsors" />
    </template>
  </Layout>
</template>
