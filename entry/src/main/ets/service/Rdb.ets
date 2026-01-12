// Rdb.ts
import { relationalStore } from '@kit.ArkData';
import CommonConstantsDb from '../constants/CommonConstantsDb';

export type SqlValue = string | number | Uint8Array | null;


export default class Rdb {
  private rdbStore: relationalStore.RdbStore | null = null;
  private readonly tableName: string;
  private readonly sqlCreateTable: string;
  private readonly columns: string[];
  private readonly context: Context; // UIAbilityContext

  constructor(context: Context, tableName: string, sqlCreateTable: string, columns: string[]) {
    this.context = context;
    this.tableName = tableName;
    this.sqlCreateTable = sqlCreateTable;
    this.columns = columns;
  }

  getRdbStore(callback: (ok: boolean) => void): void {
    if (this.rdbStore) {
      callback(true);
      return;
    }
    relationalStore.getRdbStore(this.context, CommonConstantsDb.STORE_CONFIG, (err, rdb) => {
      if (err || !rdb) {
        console.error('[RDB] getRdbStore failed:', JSON.stringify(err));
        callback(false);
        return;
      }
      this.rdbStore = rdb;
      this.rdbStore.executeSql(this.sqlCreateTable, [], (e2) => {
        if (e2) {
          console.error('[RDB] create table failed:', JSON.stringify(e2));
          callback(false);
        } else {
          callback(true);
        }
      });
    });
  }

  executeSql(sql: string, args: SqlValue[] = [], callback?: (err?: Error) => void): void {
    if (!this.rdbStore) {
      callback?.(new Error('RDB store is null'));
      return;
    }
    this.rdbStore.executeSql(sql, args, (err) => {
      if (err) {
        console.error('[RDB] SQL exec failed:', JSON.stringify(err));
        callback?.(err);
      } else {
        callback?.();
      }
    });
  }

  insertData(data: relationalStore.ValuesBucket, callback: (success: boolean, rowId?: number) => void): void {
    if (!this.rdbStore) {
      callback(false);
      return;
    }
    this.rdbStore.insert(this.tableName, data, (err, rowId) => {
      if (err) {
        console.error('[RDB] insert failed:', JSON.stringify(err));
        callback(false);
      } else {
        callback(rowId >= 0, rowId);
      }
    });
  }

  updateData(
    predicates: relationalStore.RdbPredicates,
    data: relationalStore.ValuesBucket,
    callback: (success: boolean, rowsAffected?: number) => void
  ): void {
    if (!this.rdbStore) {
      callback(false, 0);
      return;
    }
    this.rdbStore.update(data, predicates, (err, rows) => {
      if (err) {
        console.error('[RDB] update failed:', JSON.stringify(err));
        callback(false, 0);
      } else {
        callback(rows > 0, rows);
      }
    });
  }

  deleteData(
    predicates: relationalStore.RdbPredicates,
    callback: (success: boolean, rowsAffected?: number) => void
  ): void {
    if (!this.rdbStore) {
      callback(false, 0);
      return;
    }
    this.rdbStore.delete(predicates, (err, rows) => {
      if (err) {
        console.error('[RDB] delete failed:', JSON.stringify(err));
        callback(false, 0);
      } else {
        callback(rows > 0, rows);
      }
    });
  }

  query(
    predicates: relationalStore.RdbPredicates,
    callback: (rs: relationalStore.ResultSet | null) => void
  ): void {
    if (!this.rdbStore) {
      callback(null);
      return;
    }
    this.rdbStore.query(predicates, this.columns, (err, rs) => {
      if (err || !rs) {
        console.error('[RDB] query failed:', JSON.stringify(err));
        callback(null);
        return;
      }
      callback(rs);
    });
  }
}
