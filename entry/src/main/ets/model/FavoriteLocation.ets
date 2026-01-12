export interface FavoriteLocation {
  id: string;
  name: string;
  imageSource?: string;
  description?: string;
  isFavorite: boolean;
  latitude: number;
  longitude: number;
  snippet?: string;
}
