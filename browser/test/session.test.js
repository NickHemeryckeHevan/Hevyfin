import { describe, expect, it, vi } from 'vitest'

describe('taking over the Flutter web version', () => {
  it('keeps its profiles, sign-in, device and settings', async () => {
    localStorage.clear()
    // shared_preferences on the web: "flutter.<key>", JSON-encoded.
    localStorage.setItem('flutter.profiles', JSON.stringify(JSON.stringify([{ id: 'u1', name: 'Alice', token: 't1', pin: 'abc' }, { id: 'u2', name: 'Bob', token: 't2' }])))
    localStorage.setItem('flutter.userId', '"u2"')
    localStorage.setItem('flutter.userName', '"Bob"')
    localStorage.setItem('flutter.token', '"t2"')
    localStorage.setItem('flutter.deviceId', '"hevyfin-0123456789abcdef"')
    localStorage.setItem('flutter.subtitleLang', '"eng"')
    localStorage.setItem('flutter.maxMbps', '20')
    globalThis.fetch = vi.fn(async () => ({ ok: true, status: 200, text: async () => '{"Items":[]}' }))

    const s = await import('../src/state/session.js')
    const { auth } = await import('../src/api/jellyfin.js')
    await s.start()
    expect(s.profiles.value.map((p) => p.name)).toEqual(['Alice', 'Bob'])
    expect(s.profiles.value[0].pin).toBe('abc')
    expect(s.session.value).toEqual({ userId: 'u2', userName: 'Bob', token: 't2' })
    expect(auth.deviceId).toBe('hevyfin-0123456789abcdef')
    expect(s.prefs.subtitleLang).toBe('eng')
    expect(s.prefs.maxMbps).toBe(20)
    expect(s.choosing.value).toBe(true) // two profiles: "Who's watching?"
  })

  it('hashes PINs the way the apps do', async () => {
    const { hashPin } = await import('../src/state/session.js')
    // sha256("hevyfin:u1:1234"), as Profile.hashPin in lib/state/app_state.dart makes it
    expect(hashPin('u1', '1234')).toBe('a5790b12acc0f4c7c4b465d9d26e0a480fbb3535524ad8b5c3232cc9cc3cecd8')
  })
})
