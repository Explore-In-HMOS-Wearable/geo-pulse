import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import CommonConstantsDb from '../constants/CommonConstantsDb';
import Rdb from './Rdb';
import { FavoriteLocation } from '../model/FavoriteLocation';


export default class LocationTable {
  private readonly table: Rdb;

  constructor(context: common.UIAbilityContext, onReady: (ok: boolean) => void = () => {}) {
    this.table = new Rdb(
      context,
      CommonConstantsDb.FAVORITE_TABLE.tableName,
      CommonConstantsDb.FAVORITE_TABLE.sqlCreate,
      CommonConstantsDb.FAVORITE_TABLE.columns
    );
    this.table.getRdbStore(onReady);
  }


  clearAll(callback: (success: boolean) => void): void {
    const predicates = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName);
    this.table.deleteData(predicates, (ok) => callback(ok));
  }

  dropTable(callback: (success: boolean) => void): void {
    const sql = `DROP TABLE IF EXISTS ${CommonConstantsDb.FAVORITE_TABLE.tableName}`;
    this.table.executeSql(sql, [], (err?: Error) => {
      if (err) {
        console.error('Failed to drop table:', err);
        callback(false);
      } else {
        callback(true);
      }
    });
  }

  getCount(callback: (count: number) => void): void {
    const predicates = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName);
    this.table.query(predicates, (rs) => {
      if (!rs) { callback(0); return; }
      const count = rs.rowCount;
      rs.close();
      callback(count);
    });
  }

  upsertFavorite(item: FavoriteLocation, callback: (success: boolean) => void): void {
    const vb: relationalStore.ValuesBucket = {
      id: item.id,
      name: item.name,
      imageSource: item.imageSource ?? '',
      description: item.description ?? '',
      isFavorite: item.isFavorite ? 1 : 0,
      latitude: item.latitude,
      longitude: item.longitude,
      snippet: item.snippet ?? ''
    };

    const sql = `
      INSERT OR REPLACE INTO ${CommonConstantsDb.FAVORITE_TABLE.tableName}
      (id, name, imageSource, description, isFavorite, latitude, longitude, snippet)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `;
    const args = [
      vb.id as string,
      vb.name as string,
      vb.imageSource as string,
      vb.description as string,
      vb.isFavorite as number,
      vb.latitude as number,
      vb.longitude as number,
      vb.snippet as string
    ];
    this.table.executeSql(sql, args, (err?: Error) => callback(!err));
  }

  setFavorite(id: string, isFav: boolean, callback: (success: boolean) => void): void {
    const preds = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName).equalTo('id', id);
    const vb: relationalStore.ValuesBucket = { isFavorite: isFav ? 1 : 0 };
    this.table.updateData(preds, vb, (ok) => callback(ok));
  }

  updateSnippet(id: string, snippet: string, callback: (success: boolean) => void): void {
    const preds = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName).equalTo('id', id);
    const vb: relationalStore.ValuesBucket = { snippet };
    this.table.updateData(preds, vb, (ok) => callback(ok));
  }

  deleteFavorite(id: string, callback: (success: boolean) => void): void {
    const preds = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName).equalTo('id', id);
    this.table.deleteData(preds, (ok) => callback(ok));
  }

  getById(id: string, callback: (item: FavoriteLocation | null) => void): void {
    const preds = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName).equalTo('id', id);
    this.table.query(preds, (rs) => {
      if (!rs || rs.rowCount === 0 || !rs.goToFirstRow()) { rs?.close(); callback(null); return; }
      const out = this.rowToItem(rs);
      rs.close();
      callback(out);
    });
  }

  getAll(callback: (items: FavoriteLocation[]) => void, onlyFavorites = false): void {
    const preds = new relationalStore.RdbPredicates(CommonConstantsDb.FAVORITE_TABLE.tableName);
    if (onlyFavorites) {
      preds.equalTo('isFavorite', 1);
    }
    this.table.query(preds, (rs) => {
      if (!rs || rs.rowCount === 0) { rs?.close(); callback([]); return; }
      const items: FavoriteLocation[] = [];
      if (rs.goToFirstRow()) {
        do { items.push(this.rowToItem(rs)); } while (rs.goToNextRow());
      }
      rs.close();
      callback(items);
    });
  }

  /** ResultSet -> FavoriteItem */
  private rowToItem(rs: relationalStore.ResultSet): FavoriteLocation {
    const idx = (c: string) => rs.getColumnIndex(c);
    const getS = (c: string) => rs.getString(idx(c)) ?? '';
    const getN = (c: string) => Number(rs.getDouble(idx(c)) ?? 0);
    const getI = (c: string) => Number(rs.getLong(idx(c)) ?? 0);

    return {
      id: getS('id'),
      name: getS('name'),
      imageSource: getS('imageSource'),
      description: getS('description'),
      isFavorite: getI('isFavorite') === 1,
      latitude: getN('latitude'),
      longitude: getN('longitude'),
      snippet: getS('snippet')
    };
  }
}
