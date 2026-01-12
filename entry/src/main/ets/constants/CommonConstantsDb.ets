import { relationalStore } from '@kit.ArkData';

export interface TableDefinition {
  tableName: string;
  sqlCreate: string;
  columns: string[];
}

export default class CommonConstantsDb {
  static readonly STORE_CONFIG: relationalStore.StoreConfig = {
    name: 'favorites.db',
    securityLevel: relationalStore.SecurityLevel.S1
  };

  static readonly FAVORITE_TABLE: TableDefinition = {
    tableName: 'favoriteTable',
    sqlCreate: `CREATE TABLE IF NOT EXISTS favoriteTable (
      id TEXT PRIMARY KEY,         
      name TEXT,                    
      imageSource TEXT,             
      description TEXT,            
      isFavorite INTEGER,           -- 0/1
      latitude REAL,                -- marker.lat
      longitude REAL,               -- marker.lng
      snippet TEXT                  -- info window/snippet
    )`,
    columns: [
      'id', 'name', 'imageSource', 'description',
      'isFavorite', 'latitude', 'longitude', 'snippet'
    ]
  };

  static readonly RDB_TAG = '[Debug.Rdb]';
  static readonly TABLE_TAG = '[Debug.AccountTable]';
  static readonly INDEX_TAG = '[Debug.Index]';
}
