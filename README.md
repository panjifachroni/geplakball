# Geplakball

Prototipe Godot 4.7 untuk permainan bola kertas.

## Kontrol

- Jalankan proyek dengan F5.
- Ketika bola diam, klik dan tahan pemain yang memiliki bola tepat di kaki.
- Tarik mouse ke arah berlawanan dari arah tembakan, lalu lepas.
- Tarikan lebih panjang menghasilkan tembakan lebih kuat; panah dan bar menunjukkan daya.
- Klik kanan untuk membatalkan bidikan.
- Tekan R untuk mengembalikan bola dan susunan pemain ke posisi awal.

Saat bola benar-benar berhenti dan tidak terjangkau siapa pun, pemain terdekat langsung
diteleport ke posisi siap menendang, dengan bola tepat di kaki. Jangkauan tendangan
hanya 22 piksel dari kaki. Pemain tidak menembak secara otomatis.
Benturan pada 20–60% kecepatan maksimum memberi dorongan sedang; mulai 60%
memberi dorongan berat. Di bawah 20%, bola melewati pemain tanpa mendorongnya.
Ambang ini mengikuti kecepatan maksimum bola (default 1600 piksel/detik).
Collision tiang dan jaring tetap aktif untuk semua kecepatan bola.
Bidikan dan tendangan berikutnya hanya bisa dilakukan ketika kecepatan bola nol.

## Bola keluar dan restart

- Bola keluar garis samping: ditempatkan tepat pada titik lintasan melewati garis.
  Tim lawan dari penyentuh terakhir mendapat out.
- Bola keluar garis gawang setelah disentuh tim bertahan: corner untuk lawan,
  dengan bola di sudut atas atau bawah pada sisi tersebut.
- Bola keluar garis gawang setelah disentuh tim penyerang: tendangan gawang
  diambil keeper dari posisi awalnya di depan gawang, bukan dari titik bola keluar.
- Bola melewati garis di antara tiang: gol, skor bertambah, dan tim yang kebobolan
  mendapat kickoff di tengah.
- Penendang terdekat dari tim yang berhak langsung diteleport ke bola. Hanya
  penendang itu yang bisa mengambil restart; arah tembakan harus masuk lapangan.
- Setelah menendang out, pemain bergeser sekitar 140 piksel masuk lapangan
  dari titik pengambilan bola, tanpa kembali ke posisi sebelumnya.
- Setelah menendang corner, pemain bergeser masuk lapangan sekitar 150 piksel
  dari garis gawang dan 140 piksel dari garis samping. Perpindahan terjadi setelah
  animasi geplak selesai, tanpa mengubah laju bola.
- Merah mempertahankan gawang kiri; biru mempertahankan gawang kanan.
- Keeper selalu kembali ke tengah gawang setelah menendang bola atau selesai
  terdorong. Saat mengambil bola, keeper tetap di posisi tendangan sampai menembak.
- Setelah out, corner, tendangan gawang, atau gol, bola tetap bergerak dan memantul.
  Restart menunggu minimal 1,5 detik dan bola harus benar-benar berhenti sebelum
  ditempatkan ulang. Jika masih bergerak, waktu tunggu bertambah sampai berhenti.
  Keputusan dikunci sejak
  keluar pertama kali sehingga pantulan setelahnya tidak mengubah tim atau skor.
- Tiang dan jaring gawang memiliki collision. Tiang memberi pantulan keras;
  jaring belakang dan samping meredam bola.
- Jeda bisa diatur antara 1–2 detik melalui properti Restart Delay pada scene utama.

Belum ada giliran tim untuk tembakan dalam permainan terbuka.

## Pemeriksaan gameplay

Jalankan dengan executable Godot yang tersedia:

```text
godot --headless --path . --script res://tests/gameplay_smoke.gd
godot --headless --path . --script res://tests/restarts_smoke.gd
godot --headless --path . --script res://tests/goal_delay_smoke.gd
godot --headless --path . --script res://tests/restart_return_smoke.gd
godot --headless --path . --script res://tests/motion_collision_smoke.gd
godot --headless --path . --script res://tests/keeper_recovery_smoke.gd
```

Pemeriksaan mencakup arah dan daya tembakan, teleport pemain ke bola, pantulan,
dorongan benturan kuat/pelan, out, corner, pergantian tim restart, gol, collision
gawang, jeda restart, posisi keeper, dan reset saat restart masih menunggu.
