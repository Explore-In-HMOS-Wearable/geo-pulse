export interface FavoriteLocation {
  id: string;                // uuid ya da "lat:lng"
  name: string;              // marker başlığı
  imageSource?: string;      // opsiyonel liste görseli
  description?: string;      // opsiyonel açıklama
  isFavorite: boolean;       // true/false
  latitude: number;          // marker.lat
  longitude: number;         // marker.lng
  snippet?: string;          // info window/snippet
}
