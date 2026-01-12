import { geoLocationManager } from '@kit.LocationKit';
import LocationUtil from '../util/LocationUtil';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { promptAction } from '@kit.ArkUI';
import ConstantUI from '../util/ConstantUI';
import LocationTable from '../service/LocationTable';
import { FavoriteLocation } from '../model/FavoriteLocation';
import BackgroundTaskHelper from '../util/BackgroundTaskHelper';
import ProximityChecker from '../util/ProximityChecker';

@Component
struct Index {
  @State private favorites: FavoriteLocation[] = [];
  private proximityChecker: ProximityChecker = new ProximityChecker();
  @State message: string = '';
  @Consume('NavPathStack') pageStack: NavPathStack
  @State private mapOptions: mapCommon.MapOptions | null = null;
  @State private lastLocation: LocationModel | null = null;
  private favTable?: LocationTable;
  private callback?: AsyncCallback<map.MapComponentController>;
  private mapController?: map.MapComponentController;
  private mapEventManager?: map.MapEventManager;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private bgIntervalId?: number;
  @State private showNameBar: boolean = false;
  @State private newPlaceName: string = '';
  private readonly NOTIF_ID: number = 9001;

  async aboutToAppear(): Promise<void> {
    this.callback = (err: BusinessError | null, mapController: map.MapComponentController): void => {
      if (err) {
        return;
      }
      this.favTable = new LocationTable(this.context, (ok) => {
        if (ok) {
          this.loadFavoritesAndRender();
        }
      });
      this.mapController = mapController;
      this.mapEventManager = this.mapController.getEventManager();
      this.mapEventManager.on('mapLoad', (): void => {
        this.loadFavoritesAndRender();
      });
      try {
        this.mapController.setMyLocationEnabled(true);
        this.mapController.setMyLocationStyle({
          displayType: mapCommon.MyLocationDisplayType.FOLLOW
        });
      } catch (e) {}
    };

    const cb = (err: BusinessError): void => {};
    notificationManager.requestEnableNotification(this.context, cb);
    await BackgroundTaskHelper.start(this.context);
    await this.handleLocationPermissions();
    this.startBackgroundLocationPolling();
    this.showNameBar = false;
    this.newPlaceName = '';
  }

  aboutToDisappear(): void {
    this.stopBackgroundLocationPolling();
    BackgroundTaskHelper.stop(this.context);
  }

  private async checkFavoritesProximity(current: LocationModel): Promise<void> {
    const result = this.proximityChecker.check(current, this.favorites);
    if (result.found && result.favorite) {
      const title: string = 'You are near: ' + (result.favorite.name ? result.favorite.name : 'Saved location');
      const text: string = Math.floor(result.distance).toString() + ' m within range.';
      await this.notifyInfo(title, text);
    }
  }

  private async addMarkerForFavorite(f: FavoriteLocation): Promise<void> {
    if (!this.mapController) {
      return;
    }
    try {
      const opts: mapCommon.MarkerOptions = {
        position: { latitude: f.latitude, longitude: f.longitude },
        title: f.name ?? 'Pinned',
        snippet: f.snippet ?? '',
        draggable: false,
        clickable: true
      };
      await this.mapController.addMarker(opts);
    } catch (e) {}
  }

  private makeId(lat: number, lon: number): string {
    return `${lat.toFixed(6)}:${lon.toFixed(6)}`;
  }

  private async ensureNotificationSlot(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (e) {}
  }

  private async notifyInfo(title: string, text: string): Promise<void> {
    await this.ensureNotificationSlot();
    const req: notificationManager.NotificationRequest = {
      id: this.NOTIF_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title, text }
      }
    };
    try {
      await notificationManager.publish(req);
    } catch (e) {}
  }

  private getCurrentLocation(): Promise<LocationModel> {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: 10000
    };
    return geoLocationManager.getCurrentLocation(request)
      .then((result: geoLocationManager.Location): LocationModel => {
        return { lat: result.latitude, lon: result.longitude };
      })
      .catch((error: BusinessError) => {
        throw (error instanceof Error ? error : new Error(JSON.stringify(error)));
      });
  }

  private async showUserLocation(): Promise<void> {
    try {
      const location = await this.getCurrentLocation();
      this.lastLocation = location;
      this.message = `Lat: ${location.lat.toFixed(5)}\nLon: ${location.lon.toFixed(5)}`;
      if (!this.mapOptions) {
        this.mapOptions = {
          position: { target: { latitude: location.lat, longitude: location.lon }, zoom: 14 },
          myLocationControlsEnabled: true
        };
      }
      await this.checkFavoritesProximity(location);
    } catch (e) {
      if (!this.mapOptions) {
        this.mapOptions = {
          position: { target: { latitude: 0, longitude: 0 }, zoom: 2 },
          myLocationControlsEnabled: true
        };
      }
      this.message = 'Location unavailable';
    }
  }

  private async handleLocationPermissions(): Promise<void> {
    try {
      const hasPermissions: boolean = await LocationUtil.checkLocationPermissions();
      if (hasPermissions) {
        await this.showUserLocation();
      } else {
        const granted: boolean = await LocationUtil.requestLocationPermissions(this.context);
        if (granted) {
          await this.showUserLocation();
        } else {
          this.message = 'Permission denied';
          if (!this.mapOptions) {
            this.mapOptions = {
              position: { target: { latitude: 0, longitude: 0 }, zoom: 2 },
              myLocationControlsEnabled: true
            };
          }
        }
      }
    } catch (error) {
      this.message = 'Permission flow error';
    }
  }

  private startBackgroundLocationPolling(): void {
    if (this.bgIntervalId !== undefined) {
      return;
    }
    this.showUserLocation();
    this.bgIntervalId = setInterval((): void => {
      this.showUserLocation();
    }, 1000);
  }

  private stopBackgroundLocationPolling(): void {
    if (this.bgIntervalId !== undefined) {
      clearInterval(this.bgIntervalId);
      this.bgIntervalId = undefined;
    }
  }

  private loadFavoritesAndRender(): void {
    if (!this.favTable) {
      return;
    }
    this.favTable.getAll(async (items) => {
      this.favorites = items ?? [];
      if (this.mapController) {
        for (const it of this.favorites) {
          await this.addMarkerForFavorite(it);
        }
      }
    });
  }

  private async addMarkerAt(loc: LocationModel, title: string = 'Pinned'): Promise<void> {
    if (!this.mapController) {
      return;
    }
    try {
      const markerOptions: mapCommon.MarkerOptions = {
        position: { latitude: loc.lat, longitude: loc.lon },
        title,
        snippet: '',
        draggable: true,
        clickable: true
      };
      await this.mapController.addMarker(markerOptions);
    } catch (e) {}
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: msg,
      duration: 2000
    });
  }

  build(): void {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.mapOptions) {
          MapComponent({ mapOptions: this.mapOptions, mapCallback: this.callback })
            .width(ConstantUI.FULL_WIDTH)
            .height(ConstantUI.FULL_HEIGHT);
        } else {
          Text(this.message).fontSize(16).fontWeight(FontWeight.Medium);
        }
        if (this.showNameBar) {
          Column({ space: 10 }) {
            Text($r('app.string.location_name'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
            TextInput({ placeholder: 'Eg: My workplace', text: this.newPlaceName })
              .onChange((v: string): void => {
                this.newPlaceName = v;
              })
              .width(ConstantUI.FULL_WIDTH)
              .height(42)
              .backgroundColor('#2b2b2b')
              .borderRadius(10)
              .fontColor(Color.White)
              .placeholderColor('#b8b8b8')
              .padding({ left: 12, right: 12 })
            Row({ space: 10 }) {
              Button($r('app.string.cancel'))
                .onClick((): void => {
                  this.showNameBar = false;
                  this.newPlaceName = '';
                  this.showToast('Cancelled');
                })
                .backgroundColor('#d0d0d0')
                .fontColor('#333333')
                .borderRadius(12)
                .height(40)
                .layoutWeight(1)

              Button('Save')
                .onClick(async (): Promise<void> => {
                  const title: string = (this.newPlaceName ?? '').trim() || 'Pinned';
                  const loc: LocationModel | null = this.lastLocation ?? (this.mapOptions ? {
                    lat: this.mapOptions.position.target.latitude,
                    lon: this.mapOptions.position.target.longitude
                  } : null);
                  if (!loc) {
                    this.showToast('Location not ready, please try again.');
                    return;
                  }
                  await this.addMarkerAt(loc, title);
                  const item: FavoriteLocation = {
                    id: this.makeId(loc.lat, loc.lon),
                    name: title,
                    isFavorite: true,
                    latitude: loc.lat,
                    longitude: loc.lon,
                    snippet: '',
                    imageSource: '',
                    description: ''
                  };
                  this.favTable?.upsertFavorite(item, async (ok) => {
                    if (!ok) {
                    } else {
                      const idx = this.favorites.findIndex(f => f.id === item.id);
                      if (idx >= 0) {
                        this.favorites.splice(idx, 1, item);
                      } else {
                        this.favorites.push(item);
                      }
                      await this.addMarkerForFavorite(item);
                    }
                  });
                  await this.notifyInfo('Geopulse • Marker saved',
                    `${title} • ${loc.lat.toFixed(5)}, ${loc.lon.toFixed(5)}`);
                  this.newPlaceName = '';
                  this.showNameBar = false;
                  this.showToast(`Saved: ${title}`);
                })
                .fontColor(Color.White)
                .borderRadius(12)
                .height(40)
                .layoutWeight(1)
            }
          }
          .padding(16)
          .margin({ bottom: 76 })
          .width('94%')
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({
            radius: 8, color: '#00000026', offsetX: 0, offsetY: 2
          })
        }
        Button($r('app.string.add_marker'))
          .fontColor('#333333')
          .onClick((): void => {
            this.newPlaceName = '';
            this.showNameBar = true;
          })
          .fontSize(14)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({
            radius: 6, color: '#00000020', offsetX: 0, offsetY: 2
          })
          .margin({ bottom: 20 });
      }
      .width(ConstantUI.FULL_WIDTH)
      .height(ConstantUI.FULL_HEIGHT)
    }
    .hideTitleBar(true)
    .width(ConstantUI.FULL_WIDTH)
    .height(ConstantUI.FULL_HEIGHT)
  }
}

export interface LocationModel {
  lat: number;
  lon: number;
}

@Builder
export function IndexPageBuilder() {
  Index()
}