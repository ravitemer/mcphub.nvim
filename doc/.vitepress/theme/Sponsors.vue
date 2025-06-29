<script setup lang="ts">
import type { DefaultTheme } from 'vitepress/theme'
import { ref, watch, onMounted, onUnmounted, computed } from 'vue'
import { useData } from 'vitepress'

const currentSponsorIndex = ref(0)
let intervalId: ReturnType<typeof setInterval> | null = null
const INTERVAL_DURATION = 10000 // Cycle every 10 seconds

const props = defineProps<{
  sponsors: DefaultTheme.sponsors
}>()

const { page } = useData()

const sponsorCards = computed(() => props.sponsors?.cards || [])

const displaySponsor = computed(() => {
  if (sponsorCards.value.length === 0) {
    return null
  }
  return sponsorCards.value[currentSponsorIndex.value]
})

function startCycling() {
  stopCycling() // Clear any existing interval before starting a new one

  if (sponsorCards.value.length > 1) { // Only cycle if there's more than one sponsor
    intervalId = setInterval(() => {
      currentSponsorIndex.value = (currentSponsorIndex.value + 1) % sponsorCards.value.length
    }, INTERVAL_DURATION)
  }
}

// Function to stop the ad cycling interval
function stopCycling() {
  if (intervalId) {
    clearInterval(intervalId)
    intervalId = null
  }
}

// Lifecycle hook: When the component is mounted, start cycling
onMounted(() => {
  if (props.sponsors?.enabled) {
    startCycling()
  }
})

// Lifecycle hook: When the component is unmounted, stop cycling
onUnmounted(() => {
  stopCycling()
})

</script>

<template>
  <div class="VpSponsorCard">
    <!-- Use Vue's Transition component for smooth fade effects -->
    <Transition name="sponsor-fade" mode="out-in">
      <div v-if="sponsors?.enabled && displaySponsor" :key="currentSponsorIndex" class="card-content">
        <a :href="displaySponsor.href" target="_blank" rel="noopener">
          <img :src="displaySponsor.image" :alt="displaySponsor.alt">
        </a>
        <a :href="displaySponsor.href" target="_blank" rel="noopener" class="carbon-text">
          {{ displaySponsor.text }}
        </a>
        <a href="https://github.com/sponsors/ravitemer" target="_blank" rel="noopener" class="carbon-poweredby">
          Featured Sponsor
        </a>
      </div>
      <!-- Optional: Placeholder or empty state when no sponsor is displayed -->
      <div v-else>
        <!-- Content to display when no sponsor is active or enabled -->
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.VpSponsorCard {
  display: flex;
  margin-top: 10px;
  justify-content: center;
  align-items: center;
  padding: 24px;
  border-radius: 12px;
  min-height: 256px; /* Maintain height during transitions to prevent layout shifts */
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
  transition: color 0.2s;
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
  transition: color 0.2s;
}

.VpSponsorCard :deep(.carbon-poweredby:hover) {
  color: var(--vp-carbon-ads-hover-poweredby-color);
}

/* Base styles for the content container */
.card-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%; /* Ensure content fills available space within VpSponsorCard */
  /* Opacity and transition handled by Vue's Transition classes */
}

/* Vue Transition classes for fade effect */
.sponsor-fade-enter-active,
.sponsor-fade-leave-active {
  transition: opacity 0.2s ease; /* Adjust transition duration as desired */
}

.sponsor-fade-enter-from,
.sponsor-fade-leave-to {
  opacity: 0;
}

</style>
