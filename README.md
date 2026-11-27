# Geplakball

Prototipe Godot 4.7 untuk permainan bola kertas.

## Durasi pertandingan

- Pertandingan berlangsung 3 menit dengan hitung mundur `03:00` di bagian atas.
- Waktu tetap berjalan saat out, persiapan tendangan, dan selebrasi gol. Menu pause
  menghentikan timer; suara crowd tetap berjalan.
- Pada `00:00`, pertandingan berakhir, bola/pemain berhenti, dan skor dikunci.
  Tidak ada layar hasil tambahan: `aset/whistle.wav` diputar satu kali hingga
  selesai, lalu otomatis kembali ke menu utama dan musik menu dimulai.

## Kontrol

Tombol Start membuka scene `select_mode.tscn` yang menyediakan dua mode:

- **1vCPU:** tim merah dikendalikan pemain; tim biru memakai CPU tingkat Normal.
- **1v1:** dua orang bermain lokal pada satu perangkat, bergantian membidik dan
  menendang menggunakan mouse yang sama. Kedua tim dapat dikontrol manusia;
  CPU tidak berjalan. Pemain terdekat tetap mengambil bola sesuai aturan pertandingan.

Tekan Esc di pilihan mode untuk kembali ke menu utama. Reset mempertahankan mode
yang dipilih. Musik menu juga berjalan di pilihan mode dan berhenti ketika masuk pertandingan.

CPU berpikir 0,8–1,4 detik, menilai celah gawang dari posisi keeper dan jalur pemain,
serta memilih operan yang lebih terbuka. Bidikan ditinjau lagi sebelum menendang.
Arah/kekuatan lebih akurat dari mode Santai sebelumnya, dengan sedikit variasi
agar tetap bisa salah. Sesekali mencoba tembakan jauh yang berisiko.
AI mengikuti aturan jangkauan, larangan dribble, bola berhenti, dan restart yang
sama; pause, reset, dan akhir pertandingan membatalkan/menghentikan aksinya.
Scene `local_match.tscn` mewarisi pertandingan utama dengan Blue AI Enabled dimatikan.

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
memberi dorongan berat. Di bawah 20%, bola tetap memantul tanpa mendorong pemain.
Ambang ini mengikuti kecepatan maksimum bola (default 1600 piksel/detik).
Collision pemain, tiang, dan jaring tetap aktif untuk semua kecepatan bola.
Collider pemain mengikuti seluruh batas gambar yang terlihat pada pose idle dan penyet.
Bidikan dan tendangan berikutnya hanya bisa dilakukan ketika kecepatan bola nol.
Saat tendangan dilepas, hanya collision antara bola dan penendang yang diabaikan
sampai bola melewati tubuh penendang. Ini memungkinkan passing ke belakang.
Collision penendang dipulihkan setelah bola keluar dari tubuhnya, saat bola
memantul, berhenti, atau saat restart/reset. Pemain lain tetap memiliki collision
di semua kecepatan, dan bola pantulan dapat mengenai penendang lagi.
Pemain yang baru menendang tidak boleh mengambil bola lagi. Setelah bola berhenti,
pemain terdekat dari kedua tim, selain penendang terakhir, menjadi pengambil
berikutnya. Pantulan pasif tidak menghapus larangan ini; tendangan pemain lain
atau restart permainan baru menghapusnya. Tidak ada dribbling dengan sentuhan kecil.
Pemilihan memakai jarak pusat tubuh pemain ke bola saat berhenti, tanpa preferensi
tim. Pemain lama yang kebetulan masih dalam jangkauan tidak boleh melewati kandidat
yang lebih dekat. Setelah pemain terpilih diteleport, kepemilikan dikunci sampai
tendangan berikutnya agar pilihan tidak berganti hanya akibat teleport tersebut.

## Bola keluar dan restart

- Out di area serang sekitar 60–88% panjang lapangan memakai formasi referensi
  pertama: rekan penendang maju dan lawan membentuk pertahanan.
- Corner dan out di 12% terakhir dekat sudut serang memakai formasi referensi
  kedua, dengan pemain mendukung serangan/menjaga area gawang.
- Susunan dicerminkan untuk tim biru serta restart dari garis bawah. Out dekat
  garis tengah atau di area sendiri tidak mengubah formasi.
- Susunan diterapkan saat bola siap untuk restart setelah jeda, tanpa mengubah
  ukuran sprite, titik bola, pemilihan penendang, ataupun aturan tendang.

- Bola keluar garis samping: ditempatkan tepat pada titik lintasan melewati garis.
  Tim lawan dari penyentuh terakhir mendapat out.
- Bola keluar garis gawang setelah disentuh tim bertahan: corner untuk lawan,
  dengan bola di sudut atas atau bawah pada sisi tersebut.
- Bola keluar garis gawang setelah disentuh tim penyerang: tendangan gawang
  diambil keeper dari posisi awalnya di depan gawang, bukan dari titik bola keluar.
  Semua pemain kembali ke formasi awal, termasuk setelah serangan atau counter attack.
- Seluruh bola harus melewati sisi luar garis putih di antara tiang agar dianggap
  gol. Bola yang hanya menyentuh/menumpuk pada garis belum gol. Skor bertambah dan tim yang kebobolan
  mendapat kickoff di tengah.
- Penendang terdekat dari tim yang berhak langsung diteleport ke bola. Hanya
  penendang itu yang bisa mengambil restart; arah tembakan harus masuk lapangan.
- Setelah menendang out, pemain bergeser sekitar 140 piksel masuk lapangan
  dari titik pengambilan bola hanya setelah bola benar-benar berhenti. Selama bola
  melaju, penendang tetap di garis. Ini juga berlaku jika penendang out adalah keeper.
- Setelah menendang corner, pemain bergeser masuk lapangan sekitar 150 piksel
  dari garis gawang dan 140 piksel dari garis samping. Perpindahan terjadi setelah
  bola benar-benar berhenti; selama bola masih bergerak penendang tetap di sudut.
- Merah mempertahankan gawang kiri; biru mempertahankan gawang kanan.
- Keeper selalu kembali ke tengah gawang setelah menendang bola atau selesai
  terdorong. Saat mengambil bola, keeper tetap di posisi tendangan sampai menembak.
- Keeper bisa mencoba save atas/bawah saat bola bergerak menuju gawang: reaksi
  sekitar 0,2 detik, kecepatan geser 155 piksel/detik, maksimal 75 piksel per
  pembacaan, dan sedikit kesalahan arah. Tidak bergerak horizontal saat save,
  tidak mengejar bola jauh/melebar, dan tetap bisa kebobolan oleh tembakan cepat.
- Setelah formasi out/corner maju, posisi sebelumnya disimpan. Jika lawan melakukan
  tendangan counter dan kemudian keeper tim yang tadi maju memperoleh bola di kaki,
  pemain lapangan tim keeper kembali ke posisi sebelum formasi maju. Pemain counter
  mundur 80 piksel ke arah gawang sendiri. Posisi bola dan keeper pemiliknya tetap;
  reset ini berlaku sekali untuk kedua tim, bukan karena pantulan pasif saja.
- Ketika serangan formasi maju setelah out/corner direbut lawan, dua pendukung serangan
  mundur ke area sendiri di belakang garis tengah. Berlaku sekali per formasi untuk kedua
  tim. Pergantian giliran biasa tidak mengubah formasi awal secara bertahap.
- Semua penempatan ulang (formasi, pengambilan bola, kepulangan penendang dan keeper)
  memeriksa ruang antar badan saat idle dari posisi terbaru dengan celah kecil 4 piksel.
  Pose penyet tidak memperlebar ruang formasi.
  Posisi yang padat digeser ke tempat terdekat yang kosong; pemilik bola tetap di kaki bola.
- Keeper merah menggunakan `aset/keeper1.png`, keeper biru `aset/keeper2.png`,
  dengan pose idle/penyet dan collider mengikuti gambar masing-masing.
- Saat penendang lawan bersiap, keeper bergeser sedikit ke atas/bawah untuk
  menutup sisi tiang terdekat penendang, maksimal 60 piksel dari tengah gawang.
  Sprite tidak berputar; tubuh dan collision ikut bergeser. Posisi ini ditahan
  selama bola bergerak. Penendang di tengah membuat keeper kembali ke tengah.
- Jika penendang di sisi atas/bawah dekat mulut gawang (hingga 260 piksel), keeper
  merapat ke tiang tersebut sampai celah collision lebih kecil daripada diameter
  bola. Transisi bertahap pada jarak 260–480 piksel; penendang jauh tetap mendapat
  penjagaan biasa. Keeper tidak menutup kedua tiang sekaligus.
- Setelah out, corner, tendangan gawang, atau gol, bola tetap bergerak dan memantul.
  Restart menunggu minimal 1,5 detik dan bola harus benar-benar berhenti sebelum
  ditempatkan ulang. Jika masih bergerak, waktu tunggu bertambah sampai berhenti.
  Keputusan dikunci sejak
  keluar pertama kali sehingga pantulan setelahnya tidak mengubah tim atau skor.
- Tiang dan jaring gawang memiliki collision. Tiang memberi pantulan keras;
  jaring belakang dan samping meredam bola.
- Jeda bisa diatur antara 1–2 detik melalui properti Restart Delay pada scene utama.

Belum ada giliran tim untuk tembakan dalam permainan terbuka.

## Suara pertandingan

- `aset/whistle.wav`: peluit akhir pertandingan, lalu otomatis kembali ke menu
  utama setelah suara selesai. Pause tidak memotong peluit akhir.
- `aset/footie.wav`: musik berulang khusus menu utama. Berhenti ketika mulai
  pertandingan; tidak diputar di menu pause. Kembali ke menu utama memutarnya lagi.
- `aset/kicking-sounds.wav`: diputar saat tendangan benar-benar mengenai bola.
- `aset/football-crowd.wav`: mulai bersama pertandingan, berulang, dan tetap
  berjalan saat menu pause dibuka dengan Esc. Berhenti ketika meninggalkan pertandingan.
- `aset/missed-shotv1.wav`: mulai saat tembakan mendekati gawang, termasuk peluang
  yang bisa diselamatkan keeper, terkena tiang, atau meleset tipis. Jarak reaksi
  maksimal 320 piksel dari garis gawang dan proyeksi arah sekitar mulut gawang
  (margin 80 piksel). Bola jauh, menjauh, atau yang berhenti sebelum sampai tidak
  memicu reaksi. Hanya sekali per tembakan.
- `aset/GOALv1.wav`: saat gol. Kickoff disiapkan 0,3 detik sebelum suara selesai,
  dengan tetap menunggu bola berhenti. Suara gol dan hitungan kickoff ikut pause;
  crowd tetap berjalan. R menghentikan efek gol tanpa memulai ulang crowd.
- Ketika seluruh bola benar-benar masuk, suara missed shot langsung dihentikan
  dan diganti suara gol. Suara gol tidak dimulai untuk prediksi yang belum pasti.

## Pemeriksaan gameplay

Jalankan dengan executable Godot yang tersedia:

```text
godot --headless --path . --script res://tests/gameplay_smoke.gd
godot --headless --path . --script res://tests/restarts_smoke.gd
godot --headless --path . --script res://tests/goal_delay_smoke.gd
godot --headless --path . --script res://tests/restart_return_smoke.gd
godot --headless --path . --script res://tests/motion_collision_smoke.gd
godot --headless --path . --script res://tests/keeper_recovery_smoke.gd
godot --headless --path . --script res://tests/audio_smoke.gd
godot --headless --path . --script res://tests/audio_prediction_smoke.gd
godot --headless --path . --script res://tests/goal_turn_facing_smoke.gd
godot --headless --path . --script res://tests/near_post_smoke.gd
godot --headless --path . --script res://tests/back_pass_smoke.gd
godot --headless --path . --script res://tests/match_timer_smoke.gd
godot --headless --path . --script res://tests/menu_music_smoke.gd
godot --headless --path . --script res://tests/casual_ai_smoke.gd
godot --headless --path . --script res://tests/nearest_pickup_smoke.gd
godot --headless --path . --script res://tests/restart_formations_smoke.gd
godot --headless --path . --script res://tests/keeper_saves_smoke.gd
godot --headless --path . --script res://tests/counter_recovery_smoke.gd
godot --headless --path . --script res://tests/cpu_decisions_smoke.gd
```

Pemeriksaan mencakup arah dan daya tembakan, teleport pemain ke bola, pantulan,
dorongan benturan kuat/pelan, out, corner, pergantian tim restart, gol, collision
gawang, jeda restart, posisi keeper, dan reset saat restart masih menunggu.
