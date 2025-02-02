using Xmpp;

namespace Dino.Entities {

public class FileTransfer : Object {

    public const bool DIRECTION_SENT = true;
    public const bool DIRECTION_RECEIVED = false;

    public enum State {
        COMPLETE,
        IN_PROGRESS,
        NOT_STARTED,
        FAILED
    }

    public int id { get; set; default=-1; }
    public Account account { get; set; }
    public Jid counterpart { get; set; }
    public Jid ourpart { get; set; }
    public Jid? from {
        get { return direction == DIRECTION_SENT ? ourpart : counterpart; }
    }
    public Jid? to {
        get { return direction == DIRECTION_SENT ? counterpart : ourpart; }
    }
    public bool direction { get; set; }
    public DateTime time { get; set; }
    public DateTime? local_time { get; set; }
    public Encryption encryption { get; set; default=Encryption.NONE; }

    private InputStream? input_stream_ = null;
    public InputStream input_stream {
        get {
            if (input_stream_ == null) {
                File file = File.new_for_path(Path.build_filename(storage_dir, path ?? file_name));
                try {
                    input_stream_ = file.read();
                } catch (Error e) { }
            }
            return input_stream_;
        }
        set {
            input_stream_ = value;
        }
    }

    public string file_name { get; set; }
    private string? server_file_name_ = null;
    public string server_file_name {
        get { return server_file_name_ ?? file_name; }
        set { server_file_name_ = value; }
    }
    public string path { get; set; }
    public string? mime_type { get; set; }
    // TODO(hrxi): expand to 64 bit
    public int size { get; set; default=-1; }

    public State state { get; set; default=State.NOT_STARTED; }
    public int provider { get; set; }
    public string info { get; set; }

    private Database? db;
    private string storage_dir;

    public FileTransfer.from_row(Database db, Qlite.Row row, string storage_dir) {
        this.db = db;
        this.storage_dir = storage_dir;

        id = row[db.file_transfer.id];
        account = db.get_account_by_id(row[db.file_transfer.account_id]); // TODO don’t have to generate acc new

        string counterpart_jid = db.get_jid_by_id(row[db.file_transfer.counterpart_id]);
        string counterpart_resource = row[db.file_transfer.counterpart_resource];
        counterpart = Jid.parse(counterpart_jid);
        if (counterpart_resource != null) counterpart = counterpart.with_resource(counterpart_resource);

        string our_resource = row[db.file_transfer.our_resource];
        if (our_resource != null) {
            ourpart = account.bare_jid.with_resource(our_resource);
        } else {
            ourpart = account.bare_jid;
        }
        direction = row[db.file_transfer.direction];
        time = new DateTime.from_unix_utc(row[db.file_transfer.time]);
        local_time = new DateTime.from_unix_utc(row[db.file_transfer.local_time]);
        encryption = (Encryption) row[db.file_transfer.encryption];
        file_name = row[db.file_transfer.file_name];
        path = row[db.file_transfer.path];
        mime_type = row[db.file_transfer.mime_type];
        size = row[db.file_transfer.size];
        state = (State) row[db.file_transfer.state];
        provider = row[db.file_transfer.provider];
        info = row[db.file_transfer.info];

        notify.connect(on_update);
    }

    public void persist(Database db) {
        if (id != -1) return;

        this.db = db;
        Qlite.InsertBuilder builder = db.file_transfer.insert()
            .value(db.file_transfer.account_id, account.id)
            .value(db.file_transfer.counterpart_id, db.get_jid_id(counterpart))
            .value(db.file_transfer.counterpart_resource, counterpart.resourcepart)
            .value(db.file_transfer.our_resource, ourpart.resourcepart)
            .value(db.file_transfer.direction, direction)
            .value(db.file_transfer.time, (long) time.to_unix())
            .value(db.file_transfer.local_time, (long) local_time.to_unix())
            .value(db.file_transfer.encryption, encryption)
            .value(db.file_transfer.file_name, file_name)
            .value(db.file_transfer.size, size)
            .value(db.file_transfer.state, state)
            .value(db.file_transfer.provider, provider)
            .value(db.file_transfer.info, info);

        if (file_name != null) builder.value(db.file_transfer.file_name, file_name);
        if (path != null) builder.value(db.file_transfer.path, path);
        if (mime_type != null) builder.value(db.file_transfer.mime_type, mime_type);

        id = (int) builder.perform();
        notify.connect(on_update);
    }

    public File get_file() {
        return File.new_for_path(Path.build_filename(Dino.get_storage_dir(), "files", path));
    }

    private void on_update(Object o, ParamSpec sp) {
        Qlite.UpdateBuilder update_builder = db.file_transfer.update().with(db.file_transfer.id, "=", id);
        switch (sp.name) {
            case "counterpart":
                update_builder.set(db.file_transfer.counterpart_id, db.get_jid_id(counterpart));
                update_builder.set(db.file_transfer.counterpart_resource, counterpart.resourcepart); break;
            case "ourpart":
                update_builder.set(db.file_transfer.our_resource, ourpart.resourcepart); break;
            case "direction":
                update_builder.set(db.file_transfer.direction, direction); break;
            case "time":
                update_builder.set(db.file_transfer.time, (long) time.to_unix()); break;
            case "local-time":
                update_builder.set(db.file_transfer.local_time, (long) local_time.to_unix()); break;
            case "encryption":
                update_builder.set(db.file_transfer.encryption, encryption); break;
            case "file-name":
                update_builder.set(db.file_transfer.file_name, file_name); break;
            case "path":
                update_builder.set(db.file_transfer.path, path); break;
            case "mime-type":
                update_builder.set(db.file_transfer.mime_type, mime_type); break;
            case "size":
                update_builder.set(db.file_transfer.size, size); break;
            case "state":
                if (state == State.IN_PROGRESS) return;
                update_builder.set(db.file_transfer.state, state); break;
            case "provider":
                update_builder.set(db.file_transfer.provider, provider); break;
            case "info":
                update_builder.set(db.file_transfer.info, info); break;
        }
        update_builder.perform();
    }
}

}
