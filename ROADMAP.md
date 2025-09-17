# Portfolio - Roadmap & Technical Debt

## 🔴 High Priority

### Issue #86 - Migrate hardcoded albums to database (3-4h)
**Status**: Todo  
**Category**: Data Migration  
**Impact**: Removes data duplication, centralizes album management

**Problem**:
- Timeline and Gallery LiveViews have hardcoded album data mixed with database albums
- Source of truth is unclear
- Double maintenance effort to update an album
- Risk of data desynchronization

**Files affected**:
- `lib/portfolio_web/live/photography_live/timeline.ex` (lines 22-215)
- `lib/portfolio_web/live/photography_live/gallery.ex` (lines 7-17, 23-45)

**Solution**:
1. Create migration script to import hardcoded albums into database
2. Remove `@data` module attribute from Timeline
3. Refactor Gallery to use `Photography.get_album_by_slug/2`
4. Add `get_album_by_slug/2` function to Photography context
5. Update tests

**Acceptance Criteria**:
- [ ] All hardcoded albums imported to DB
- [ ] Timeline uses only DB data
- [ ] Gallery uses only DB data
- [ ] Tests pass
- [ ] No breaking changes to URLs

---

### Issue #87 - Extract PhotoUpload and PhotoGrid LiveComponents (3-4h)
**Status**: Todo  
**Category**: Refactoring  
**Impact**: Improves maintainability, reduces God LiveView complexity

**Problem**:
- `AlbumLive.Edit` has too many responsibilities (150 lines, 10 handle_event callbacks)
- Complex state management (`:editing_photo`, `:photo_form`, `:reordering_mode`, `:temp_photo_order`)
- Difficult to test and maintain

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/edit.ex`
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`

**Solution**:
1. Create `PhotoUploadComponent` for photo upload logic
2. Create `PhotoGridComponent` for photo display + actions
3. Create `PhotoEditModal` component for individual photo editing
4. Create `PhotoReorderComponent` for drag & drop reordering
5. Update Edit LiveView to orchestrate components
6. Update template to use new components

**New files**:
- `lib/portfolio_web/live/admin/album_live/photo_upload_component.ex`
- `lib/portfolio_web/live/admin/album_live/photo_grid_component.ex`
- `lib/portfolio_web/live/admin/album_live/photo_edit_modal.ex`
- `lib/portfolio_web/live/admin/album_live/photo_reorder_component.ex`

**Acceptance Criteria**:
- [ ] Edit LiveView reduced to <80 lines
- [ ] Each component has single responsibility
- [ ] Photo upload works as before
- [ ] Photo editing works as before
- [ ] Photo reordering works as before
- [ ] Tests pass

---

### Issue #88 - Internationalize admin interface (1-2h)
**Status**: Todo  
**Category**: I18n  
**Impact**: Language consistency, enables multi-language admin

**Problem**:
- Admin interface has hardcoded French strings
- Inconsistent with rest of codebase (English)
- Cannot be internationalized

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/form_component.ex`
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`
- `lib/portfolio_web/live/admin/album_live/index.html.heex`
- `lib/portfolio_web/live/auth_live/login.html.heex`

**Solution**:
1. Replace all hardcoded strings with `gettext/1` calls
2. Add translations to `priv/gettext/*/LC_MESSAGES/default.po`
3. Update flash messages to use gettext

**Acceptance Criteria**:
- [ ] No hardcoded French strings in admin
- [ ] All strings use gettext
- [ ] French translations added
- [ ] English translations added
- [ ] Admin works in both languages

---

## 🟡 Medium Priority

### Issue #89 - Add telemetry helper to Service behaviour (1h)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Reduces code duplication (5 occurrences)

**Problem**:
- Pattern `start_time / result / duration / telemetry.execute` duplicated in all 5 services
- Violates DRY principle
- Harder to maintain consistent telemetry

**Files affected**:
- `lib/portfolio/services/service.ex`
- `lib/portfolio/services/photography/album_publication_service.ex`
- `lib/portfolio/services/photography/photo_upload_service.ex`
- `lib/portfolio/services/photography/album_deletion_service.ex`
- `lib/portfolio/services/auth/magic_link_auth_service.ex`

**Solution**:
1. Add `with_telemetry/3` macro to Service behaviour
2. Update all services to use the helper
3. Ensure telemetry events remain identical
4. Update tests if needed

**Acceptance Criteria**:
- [ ] `with_telemetry/3` helper implemented
- [ ] All 5 services refactored to use helper
- [ ] Telemetry events unchanged
- [ ] Tests pass
- [ ] No breaking changes

---

### Issue #90 - Optimize PhotoRepository.reorder/2 performance (2h)
**Status**: Todo  
**Category**: Performance  
**Impact**: N queries → 1 query for photo reordering

**Problem**:
- `reorder/2` executes N separate UPDATE queries for N photos
- For 100 photos = 100 queries
- Performance degradation on large albums

**File affected**:
- `lib/portfolio/photography/repositories/photo_repository.ex` (lines 132-142)

**Solution**:
Use Ecto fragments with CASE WHEN for single-query batch update:

```elixir
|> Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
  now = DateTime.utc_now()
  
  # Build CASE WHEN expression for all photos at once
  case_expr = 
    Enum.with_index(photo_ids)
    |> Enum.reduce(dynamic([p], p.display_order), fn {photo_id, index}, acc ->
      dynamic([p], fragment("CASE WHEN ? = ? THEN ? ELSE ? END",
        p.id, ^photo_id, ^index, ^acc))
    end)
  
  {count, _} =
    from(p in Photo, where: p.id in ^photo_ids)
    |> repo.update_all(set: [display_order: case_expr, updated_at: now])
  
  {:ok, count}
end)
```

**Acceptance Criteria**:
- [ ] Single UPDATE query for all photos
- [ ] Functionality unchanged
- [ ] Tests pass
- [ ] Benchmark shows improvement for >20 photos

---

### Issue #91 - Add comprehensive tests for Query Objects (2-3h)
**Status**: Todo  
**Category**: Testing  
**Impact**: Increases confidence in refactoring, prevents regressions

**Problem**:
- Only `with_photo_count/1` and `with_cover_photo_only/1` have tests
- Other query functions (`by_type/2`, `published/1`, `unpublished/1`, `order_by_date_desc/1`) are untested
- No guarantee SQL queries are correct
- Risk of regression during refactoring

**File to update**:
- `test/portfolio/photography/queries/album_query_test.exs`

**Solution**:
Add test coverage for all AlbumQuery functions:
- `by_type/2` - test filtering by album type
- `published/1` - test filtering published albums
- `unpublished/1` - test filtering unpublished albums
- `order_by_date_desc/1` - test ordering by date
- `with_preload/2` - test preloading associations

**Acceptance Criteria**:
- [ ] 100% test coverage on AlbumQuery
- [ ] Each query function has at least 2 test cases
- [ ] Tests verify correct SQL generation
- [ ] Tests verify correct results
- [ ] All tests pass

---

## 🟢 Low Priority

### Issue #92 - Translate Photography context documentation to English (1h)
**Status**: Todo  
**Category**: Documentation  
**Impact**: Consistency, accessibility for international contributors

**Problem**:
- Photography context moduledoc is in French
- Rest of codebase (specs, comments) is in English
- Inconsistent documentation language

**File affected**:
- `lib/portfolio/photography.ex` (lines 1-35)

**Solution**:
1. Translate all French documentation to English
2. Keep French domain terms if they represent ubiquitous language
3. Update examples to use English descriptions

**Acceptance Criteria**:
- [ ] All documentation in English
- [ ] No French comments or docs remain
- [ ] Examples updated
- [ ] Ubiquitous language section remains clear

---

### Issue #93 - Centralize cache keys management (1h)
**Status**: Todo  
**Category**: Maintainability  
**Impact**: Better cache invalidation, more flexible cache strategy

**Problem**:
- Cache keys hardcoded in `Photography.invalidate_albums_cache/0`
- Only 2 specific cache keys invalidated
- New preload combinations not invalidated
- No central cache key management

**Files affected**:
- `lib/portfolio/photography.ex` (lines 106-107, 135-149)

**Solution**:
1. Create `Portfolio.CacheKeys` module
2. Centralize all cache key generation
3. Add function to list all matching cache keys
4. Update invalidation to use pattern matching

**New file**:
- `lib/portfolio/cache_keys.ex`

**Example**:
```elixir
defmodule Portfolio.CacheKeys do
  def published_albums_by_year(preloads \\ []) do
    {:published_albums_by_year, Enum.sort(preloads)}
  end
  
  def all_published_albums_keys do
    Cachex.keys!(:portfolio_cache)
    |> Enum.filter(&match?({:published_albums_by_year, _}, &1))
  end
end
```

**Acceptance Criteria**:
- [ ] CacheKeys module created
- [ ] All cache key generation centralized
- [ ] Invalidation uses pattern matching
- [ ] Tests pass
- [ ] Cache works as before

---

### Issue #94 - Add email validation to Login LiveView (30min)
**Status**: Todo  
**Category**: UX  
**Impact**: Better user experience, immediate feedback

**Problem**:
- No client-side validation before submitting email
- User waits for request to know if email is malformed
- Poor UX

**File affected**:
- `lib/portfolio_web/live/auth_live/login.ex`

**Solution**:
1. Add changeset for email validation
2. Add `phx-change="validate"` event
3. Show validation errors in real-time
4. Validate format before submitting

**Acceptance Criteria**:
- [ ] Email validation on input change
- [ ] Error displayed if invalid format
- [ ] Submit disabled if invalid
- [ ] Tests pass

---

### Issue #95 - Remove get_or_create_user/1 duplication (15min)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Removes duplication between Auth context and MagicLinkAuthService

**Problem**:
- `get_or_create_user/1` in Auth context
- `fetch_or_create_user/1` in MagicLinkAuthService (private)
- Same logic, different names
- Confusion about which to use

**File affected**:
- `lib/portfolio/auth.ex` (lines 37-62)

**Solution**:
Remove `get_or_create_user/1` from Auth context, keep only in service as private function.

**Acceptance Criteria**:
- [ ] `get_or_create_user/1` removed from Auth context
- [ ] Service continues using private `fetch_or_create_user/1`
- [ ] No breaking changes to public API
- [ ] Tests pass

---

### Issue #96 - Extract max filename length constant in LocalStorage (5min)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Removes magic number, adds clarity

**Problem**:
- `String.slice(0, 50)` hardcoded without explanation
- Magic number difficult to adjust if needed

**File affected**:
- `lib/portfolio/photography/storage/local_storage.ex` (line 91)

**Solution**:
```elixir
@max_filename_length 50  # Max base name length to prevent filesystem issues

defp build_filename(original_name, hash, extension) do
  base_name =
    original_name
    |> Path.rootname()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_filename_length)
  # ...
end
```

**Acceptance Criteria**:
- [ ] Module attribute `@max_filename_length` added
- [ ] Magic number replaced
- [ ] Comment explains rationale
- [ ] Tests pass

---

## 📊 Summary

- **High Priority**: 3 issues (8-10h total)
- **Medium Priority**: 3 issues (5-6h total)
- **Low Priority**: 5 issues (3-4h total)

**Total Estimated Effort**: 16-20 hours

**Next Steps**:
1. Start with high priority issues
2. Create feature branches for each issue
3. Run full test suite after each change
4. Update this roadmap as issues are completed
