// The pages, each its own address (back button, new tabs and links work), and each loaded
// only when it's first opened. The same addresses as the apps (lib/router.dart).
import { createRouter, createWebHistory } from 'vue-router'
import Home from './views/Home.vue'

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', component: Home, meta: { tab: 0 } },
    { path: '/shows', component: () => import('./views/Browse.vue'), props: { kind: 'Series' }, meta: { tab: 1 } },
    { path: '/movies', component: () => import('./views/Browse.vue'), props: { kind: 'Movie' }, meta: { tab: 2 } },
    { path: '/new', component: () => import('./views/Discover.vue'), meta: { tab: 3 } },
    { path: '/my-list', component: () => import('./views/MyList.vue'), meta: { tab: 4 } },
    { path: '/genre/:name', component: () => import('./views/Genre.vue'), props: true },
    { path: '/search', component: () => import('./views/Search.vue') },
    { path: '/item/:id', component: () => import('./views/Details.vue'), props: true },
    { path: '/person/:id', component: () => import('./views/Person.vue'), props: true },
    { path: '/person/tmdb/:tmdb', component: () => import('./views/Person.vue'), props: true },
    { path: '/request/:type/:tmdb', component: () => import('./views/SeerrDetails.vue'), props: true },
    { path: '/collections', component: () => import('./views/Collections.vue') },
    { path: '/tonight', component: () => import('./views/Tonight.vue') },
    { path: '/settings', component: () => import('./views/Settings.vue') },
    { path: '/play/:id', component: () => import('./views/Player.vue'), props: true, meta: { bare: true } },
    { path: '/:rest(.*)*', redirect: '/' },
  ],
  // Back to where the page was; a new page starts at the top.
  scrollBehavior: (to, from, saved) => saved || (to.path === from.path ? undefined : { top: 0 }),
})
