package io.github.nickhemeryckehevan.hevyfin

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram

/// Google TV's "Continue watching" row: Hevyfin's started and next-up titles, each opening
/// straight into the player (hevyfin://play/<id>). Rows are matched by the Jellyfin id, so a
/// sync updates them in place and drops the ones that are finished.
object WatchNext {
    @SuppressLint("RestrictedApi")
    fun sync(context: Context, items: List<Map<String, Any?>>) {
        val resolver = context.contentResolver
        val existing = mutableMapOf<String, Long>()
        resolver.query(TvContractCompat.WatchNextPrograms.CONTENT_URI, WatchNextProgram.PROJECTION, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val p = WatchNextProgram.fromCursor(c)
                p.internalProviderId?.let { existing[it] = p.id }
            }
        }
        val keep = mutableSetOf<String>()
        for (item in items) {
            val id = item["id"] as? String ?: continue
            keep.add(id)
            val program = build(item)
            val known = existing[id]
            if (known != null) {
                resolver.update(TvContractCompat.buildWatchNextProgramUri(known), program.toContentValues(), null, null)
            } else {
                resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues())
            }
        }
        for ((id, row) in existing) {
            if (id !in keep) resolver.delete(TvContractCompat.buildWatchNextProgramUri(row), null, null)
        }
    }

    @SuppressLint("RestrictedApi")
    private fun build(item: Map<String, Any?>): WatchNextProgram {
        val id = item["id"] as String
        val episode = item["episode"] == true
        val b = WatchNextProgram.Builder()
            .setType(if (episode) TvContractCompat.PreviewPrograms.TYPE_TV_EPISODE else TvContractCompat.PreviewPrograms.TYPE_MOVIE)
            .setWatchNextType(
                if (item["started"] == true) TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE
                else TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_NEXT,
            )
            .setLastEngagementTimeUtcMillis((item["lastPlayed"] as? Number)?.toLong() ?: System.currentTimeMillis())
            .setTitle(item["title"] as? String ?: "")
            .setInternalProviderId(id)
            .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse("hevyfin://play/$id")))
            .setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
        (item["image"] as? String)?.let { b.setPosterArtUri(Uri.parse(it)) }
        (item["description"] as? String)?.let { b.setDescription(it) }
        (item["durationMs"] as? Number)?.let { b.setDurationMillis(it.toInt()) }
        (item["positionMs"] as? Number)?.let { b.setLastPlaybackPositionMillis(it.toInt()) }
        if (episode) {
            (item["episodeTitle"] as? String)?.let { b.setEpisodeTitle(it) }
            (item["season"] as? Number)?.let { b.setSeasonNumber(it.toInt()) }
            (item["number"] as? Number)?.let { b.setEpisodeNumber(it.toInt()) }
        }
        return b.build()
    }
}
