import { geoLocationManager } from "@kit.LocationKit";
import LocationUtil from "../util/LocationUtil";
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from '@kit.AbilityKit';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import promptAction from '@ohos.promptAction';
import { notificationManager } from '@kit.NotificationKit';
import ConstantUI from "../util/ConstantUI";
import LocationTable from "../service/LocationTable";
import { FavoriteLocation } from "../model/FavoriteLocation";

@Component
struct Index {
	@State private favorites: FavoriteLocation[] = [];

	private lastGlobalNotifyTs: number = 0;
	private readonly MIN_GLOBAL_INTERVAL_MS: number = 60 * 1000;

	private readonly PROXIMITY_METERS: number = 100;
	private readonly NOTIFY_COOLDOWN_MS: number = 30 * 60 * 1000;
	private lastNotified: Map<string, number> = new Map();

	private notifiedOnce: Set<string> = new Set();

	@State message: string = '';
	@Consume('NavPathStack') pageStack: NavPathStack
	private TAG: string = "HuaweiMapDemo";
	@State private mapOptions: mapCommon.MapOptions | null = null;
	@State private lastLocation: LocationModel | null = null;
	private favTable?: LocationTable;

	private callback?: AsyncCallback<map.MapComponentController>;
	private mapController?: map.MapComponentController;
	private mapEventManager?: map.MapEventManager;

	private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
	private bgIntervalId?: number;
	private readonly BG_INTERVAL_MS: number = 30_000;

	@State private showNameBar: boolean = false;
	@State private newPlaceName: string = '';

	private readonly NOTIF_ID: number = 9001;

	async aboutToAppear(): Promise<void> {
		this.callback = (err: BusinessError | null, mapController: map.MapComponentController): void => {
			if (err) {
				console.error(this.TAG, `map init error: ${JSON.stringify(err)}`);
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
				console.info(this.TAG, 'on-mapLoad');
				this.loadFavoritesAndRender();
			});

			try {
				this.mapController.setMyLocationEnabled(true);
				this.mapController.setMyLocationStyle({
					displayType: mapCommon.MyLocationDisplayType.FOLLOW
				});
			} catch (e) {
				console.error(this.TAG, `setMyLocation error: ${JSON.stringify(e)}`);
			}
		};

		const cb = (err: BusinessError): void => {
			if (err) {
				console.error('[ANS] requestEnableNotification failed:', err.code, err.message);
			} else {
				console.info('[ANS] requestEnableNotification success');
			}
		};
		notificationManager.requestEnableNotification(this.context, cb);

		await this.startBackgroundRunning();
		await this.handleLocationPermissions();
		this.startBackgroundLocationPolling();

		this.showNameBar = false;
		this.newPlaceName = '';
	}
	private distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
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
	private async checkFavoritesProximity(current: LocationModel): Promise<void> {
		if (!this.favorites || this.favorites.length === 0) {
			return;
		}
		const now = Date.now();
		if (now - this.lastGlobalNotifyTs < this.MIN_GLOBAL_INTERVAL_MS) {
			return;
		}
		let foundAny: boolean = false;
		let bestFav: FavoriteLocation | null = null;
		let bestDist: number = 0;

		for (let i = 0; i < this.favorites.length; i++) {
			const f: FavoriteLocation = this.favorites[i];
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
		if (!foundAny || bestFav === null) {
			return;
		}

		const title: string = 'You are near: ' + (bestFav.name ? bestFav.name : 'Saved location');
		const text: string = Math.floor(bestDist).toString() + ' m within range.';


		await this.notifyInfo(title, text);
		this.notifiedOnce.add(bestFav.id);
		this.lastGlobalNotifyTs = now;
	}

	private async addMarkerForFavorite(f: FavoriteLocation): Promise<void> {
		if (!this.mapController) return;
		try {
			const opts: mapCommon.MarkerOptions = {
				position: { latitude: f.latitude, longitude: f.longitude },
				title: f.name ?? 'Pinned',
				snippet: f.snippet ?? '',
				draggable: false,
				clickable: true
			};
			await this.mapController.addMarker(opts);
		} catch (e) {
			console.error(this.TAG, `addMarkerForFavorite error: ${JSON.stringify(e)}`);
		}
	}


	aboutToDisappear(): void {
		this.stopBackgroundLocationPolling();
		this.stopBackgroundRunning();
	}
	private makeId(lat: number, lon: number): string {
		return `${lat.toFixed(6)}:${lon.toFixed(6)}`;
	}

	private async ensureNotificationSlot(): Promise<void> {
		try {
			await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
		} catch (e) {
			console.warn('[NOTIF] addSlot warn: ' + JSON.stringify(e));
		}
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
			console.info('[NOTIF] published');
		} catch (e) {
			console.error('[NOTIF] publish error: ' + JSON.stringify(e));
		}
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
			console.info(this.TAG, this.message + "Location");

			if (!this.mapOptions) {
				this.mapOptions = {
					position: { target: { latitude: location.lat, longitude: location.lon }, zoom: 14 },
					myLocationControlsEnabled: true
				};
			}

			await this.checkFavoritesProximity(location);

		} catch (e) {
			console.error(this.TAG, `getCurrentLocation error: ${JSON.stringify(e)}`);
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
				const granted: boolean = await LocationUtil.requestLocationPermissions();
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
			console.error(this.TAG, `handleLocationPermissions error: ${JSON.stringify(error)}`);
			this.message = 'Permission flow error';
		}
	}

	private startBackgroundLocationPolling(): void {
		if (this.bgIntervalId !== undefined) return;
		this.showUserLocation();
		this.bgIntervalId = setInterval((): void => {
			this.showUserLocation();
		}, 1000);
		console.info(this.TAG, 'Background location polling started.');
	}

	private stopBackgroundLocationPolling(): void {
		if (this.bgIntervalId !== undefined) {
			clearInterval(this.bgIntervalId);
			this.bgIntervalId = undefined;
		}
	}

	private async startBackgroundRunning(): Promise<void> {
		const info: wantAgent.WantAgentInfo = {
			wants: [{
				bundleName: this.context.abilityInfo.bundleName,
				abilityName: this.context.abilityInfo.name
			}],
			operationType: wantAgent.OperationType.START_ABILITY,
			requestCode: 0,
			wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
		};

		try {
			const agent = await wantAgent.getWantAgent(info);
			await backgroundTaskManager.startBackgroundRunning(
				this.context,
				backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
				agent
			);
			console.info(this.TAG, 'Background running started.');
		} catch (e) {
			const err = e as BusinessError;
			console.error(this.TAG, `Failed to start background running: ${err.code} - ${err.message}`);
		}
	}

	private async stopBackgroundRunning(): Promise<void> {
		try {
			await backgroundTaskManager.stopBackgroundRunning(this.context);
			console.info(this.TAG, 'Background running stopped.');
		} catch (e) {
			const err = e as BusinessError;
			console.error(this.TAG, `Failed to stop background running: ${err.code} - ${err.message}`);
		}
	}
	private loadFavoritesAndRender(): void {
		if (!this.favTable) return;
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
		if (!this.mapController) return;
		try {
			const markerOptions: mapCommon.MarkerOptions = {
				position: { latitude: loc.lat, longitude: loc.lon },
				title,
				snippet: '',
				draggable: true,
				clickable: true
			};
			await this.mapController.addMarker(markerOptions);
		} catch (e) {
			console.error(this.TAG, `addMarker error: ${JSON.stringify(e)}`);
		}
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

						TextInput({ placeholder: 'Eg: My workplace', text: this.newPlaceName })
							.onChange((v: string): void => { this.newPlaceName = v; })
							.width(ConstantUI.FULL_WIDTH)
							.height(42)
							.backgroundColor(Color.Black)
							.borderRadius(10)
							.fontColor(Color.White)
							.fontColor(Color.White)
							.padding({ left: 12, right: 12 })

						Row({ space: 10 }) {
							Button($r('app.string.cancel'))
								.onClick((): void => {
									this.showNameBar = false;
									this.newPlaceName = '';
									promptAction.showToast({ message: 'Cancelled' });
								})
								.backgroundColor('#eeeeee')
								.fontColor(Color.Black)
								.borderRadius(12)
								.height(40)
								.layoutWeight(1)

							Button($r('app.string.save'))
								.onClick(async (): Promise<void> => {
									const title: string = (this.newPlaceName ?? '').trim() || 'Pinned';

									let loc: LocationModel | null = this.lastLocation
										?? (this.mapOptions ? { lat: this.mapOptions.position.target.latitude, lon: this.mapOptions.position.target.longitude } : null);

									if (!loc) {
										promptAction.showToast({ message: 'Location not ready, please try again.' });
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
											console.warn('Favorite upsert failed');
										} else {

											const idx = this.favorites.findIndex(f => f.id === item.id);
											if (idx >= 0) this.favorites.splice(idx, 1, item);
											else this.favorites.push(item);

											await this.addMarkerForFavorite(item);
										}
									});

									await this.notifyInfo('Geopulse • Marker saved', `${title} • ${loc.lat.toFixed(5)}, ${loc.lon.toFixed(5)}`);
									this.newPlaceName = '';
									this.showNameBar = false;
									promptAction.showToast({ message: `Kaydedildi: ${title}` });
								})


								.backgroundColor('#1E90FF')
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
					.shadow({ radius: 8, color: '#00000026', offsetX: 0, offsetY: 2 })
				}

				Button($r('app.string.add_marker'))
					.fontColor(Color.Black)
					.onClick((): void => {
						this.newPlaceName = '';
						this.showNameBar = true;
					})
					.fontSize(14)
					.backgroundColor(Color.White)
					.borderRadius(16)
					.shadow({ radius: 6, color: '#00000020', offsetX: 0, offsetY: 2 })
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
