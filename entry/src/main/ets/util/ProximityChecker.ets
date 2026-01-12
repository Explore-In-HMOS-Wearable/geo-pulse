import { FavoriteLocation } from '../model/FavoriteLocation';
import { LocationModel } from '../pages/Index';

export interface ProximityResult {
  found: boolean;
  favorite: FavoriteLocation | null;
  distance: number;
}

export default class ProximityChecker {
  private lastGlobalNotifyTs: number = 0;
  private readonly MIN_GLOBAL_INTERVAL_MS: number = 60 * 1000;
  private readonly PROXIMITY_METERS: number = 100;
  private notifiedOnce: Set<string> = new Set();

  distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000;
    const toRad = (x: number) => x * Math.PI / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  check(current: LocationModel, favorites: FavoriteLocation[]): ProximityResult {
    const emptyResult: ProximityResult = {
      found: false,
      favorite: null,
      distance: 0
    };

    if (!favorites || favorites.length === 0) {
      return emptyResult;
    }

    const now = Date.now();
    if (now - this.lastGlobalNotifyTs < this.MIN_GLOBAL_INTERVAL_MS) {
      return emptyResult;
    }

    let foundAny: boolean = false;
    let bestFav: FavoriteLocation | null = null;
    let bestDist: number = 0;

    for (let i = 0; i < favorites.length; i++) {
      const f: FavoriteLocation = favorites[i];
      if (this.notifiedOnce.has(f.id)) {
        continue;
      }
      const d: number = this.distanceMeters(current.lat, current.lon, f.latitude, f.longitude);
      if (d <= this.PROXIMITY_METERS) {
        if (!foundAny || d < bestDist) {
          foundAny = true;
          bestFav = f;
          bestDist = d;
        }
      }
    }

    if (foundAny && bestFav !== null) {
      this.notifiedOnce.add(bestFav.id);
      this.lastGlobalNotifyTs = now;
      const successResult: ProximityResult = {
        found: true,
        favorite: bestFav,
        distance: bestDist
      };
      return successResult;
    }

    return emptyResult;
  }
}