<script setup lang="ts">
import type { DefaultTheme } from 'vitepress/theme'
import { ref, watch, onMounted } from 'vue'
import { useData } from 'vitepress'

const { page } = useData()
const props = defineProps<{
  sponsors: DefaultTheme.sponsors
}>()

const sponsors = props.sponsors

const container = ref()

let currentCard = ref(0)
//Cycle through the ads on every new page
function refresh() {
  if (sponsors && sponsors.cards) {
    const cards = sponsors.cards
    const index = (currentCard.value) % cards.length
    const card = cards[index]
    currentCard.value = index + 1
    // Clear existing content
    container.value.innerHTML = ''

    const link = document.createElement('a')
    link.href = card.href
    link.target = '_blank'
    link.rel = 'noopener'

    const img = document.createElement('img')
    img.src = card.image
    img.alt = card.alt

    const cardContent = document.createElement('div')
    cardContent.className = 'card-content'

    link.appendChild(img)
    cardContent.appendChild(link)

    const title = document.createElement('a')
    title.href = card.href
    title.target = '_blank'
    title.rel = 'noopener'
    title.className = 'carbon-text'
    title.textContent = card.text
    cardContent.appendChild(title)

    const poweredBy = document.createElement("a")
    poweredBy.className = "carbon-poweredby"
    poweredBy.textContent = "Featured Sponsor"
    poweredBy.href = "https://github.com/sponsors/ravitemer"
    poweredBy.target = '_blank'
    poweredBy.rel = 'noopener'
    cardContent.appendChild(poweredBy)

    container.value.appendChild(cardContent)
  }
}

let isInitialized = false
function init() {
  if (!isInitialized) {
    isInitialized = true
    refresh()
  }
}
watch(() => page.value.relativePath, () => {
  if (isInitialized) {
    refresh()
  }
})

// no need to account for option changes during dev, we can just
// refresh the page
if (sponsors && sponsors.enabled) {
  onMounted(() => {
    init()
  })
}
</script>

<template>
  <div class="VpSponsorCard" ref="container" />
</template>

<style scoped>
.VpSponsorCard {
  display: flex;
  margin-top: 10px;
  /* margin-left: 10px; */
  justify-content: center;
  align-items: center;
  padding: 24px;
  border-radius: 12px;
  min-height: 256px;
  text-align: center;
  line-height: 18px;
  font-size: 12px;
  font-weight: 500;
  background-color: var(--vp-carbon-ads-bg-color);
}

.VpSponsorCard :deep(img) {
  margin: 0 auto;
  border-radius: 6px;
}

.VpSponsorCard :deep(.carbon-text) {
  display: block;
  margin: 0 auto;
  padding-top: 12px;
  color: var(--vp-carbon-ads-text-color);
  transition: color 0.25s;
}

.VpSponsorCard :deep(.carbon-text:hover) {
  color: var(--vp-carbon-ads-hover-text-color);
}

.VpSponsorCard :deep(.carbon-poweredby) {
  display: block;
  padding-top: 6px;
  font-size: 11px;
  font-weight: 500;
  color: var(--vp-carbon-ads-poweredby-color);
  text-transform: uppercase;
  transition: color 0.25s;
}

.VpSponsorCard :deep(.carbon-poweredby:hover) {
  color: var(--vp-carbon-ads-hover-poweredby-color);
}

.VpSponsorCard :deep(> div) {
  display: none;
}

.VpSponsorCard :deep(> div:first-of-type) {
  display: block;
}

.card-content {
  display: flex;
  flex-direction: column;
  align-items: center;
}
</style>
