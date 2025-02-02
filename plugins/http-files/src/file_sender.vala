using Dino.Entities;
using Xmpp;
using Gee;

namespace Dino.Plugins.HttpFiles {

public class HttpFileSender : FileSender, Object {
    private StreamInteractor stream_interactor;
    private Database db;
    private HashMap<Account, long> max_file_sizes = new HashMap<Account, long>(Account.hash_func, Account.equals_func);

    public HttpFileSender(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        stream_interactor.stream_negotiated.connect(on_stream_negotiated);
        stream_interactor.get_module(MessageProcessor.IDENTITY).build_message_stanza.connect(check_add_oob);
    }

    public async FileSendData? prepare_send_file(Conversation conversation, FileTransfer file_transfer) throws FileSendError {
        HttpFileSendData send_data = new HttpFileSendData();
        if (send_data == null) return null;

        Xmpp.XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) return null;

        try {
            var slot_result = yield stream_interactor.module_manager.get_module(file_transfer.account, Xmpp.Xep.HttpFileUpload.Module.IDENTITY).request_slot(stream, file_transfer.server_file_name, file_transfer.size, file_transfer.mime_type);
            send_data.url_down = slot_result.url_get;
            send_data.url_up = slot_result.url_put;
        } catch (Xep.HttpFileUpload.HttpFileTransferError e) {
            throw new FileSendError.UPLOAD_FAILED("Http file upload XMPP error: %s".printf(e.message));
        }

        return send_data;
    }

    public async void send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data) throws FileSendError {
        HttpFileSendData? send_data = file_send_data as HttpFileSendData;
        if (send_data == null) return;

        yield upload(file_transfer, send_data);

        file_transfer.info = send_data.url_down; // store the message content temporarily so the message gets filtered out

        Entities.Message message = stream_interactor.get_module(MessageProcessor.IDENTITY).create_out_message(send_data.url_down, conversation);

        message.encryption = send_data.encrypt_message ? conversation.encryption : Encryption.NONE;
        stream_interactor.get_module(MessageProcessor.IDENTITY).send_message(message, conversation);

        file_transfer.info = message.id.to_string();

        ContentItem? content_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_item(conversation, 1, message.id);
        if (content_item != null) {
            stream_interactor.get_module(ContentItemStore.IDENTITY).set_item_hide(content_item, true);
        }
    }

    public bool can_send(Conversation conversation, FileTransfer file_transfer) {
        if (!max_file_sizes.has_key(conversation.account)) return false;

        return file_transfer.size < max_file_sizes[conversation.account];
    }

    public bool is_upload_available(Conversation conversation) {
        lock (max_file_sizes) {
            return max_file_sizes.has_key(conversation.account);
        }
    }

    public long get_max_file_size(Account account) {
        lock (max_file_sizes) {
            return max_file_sizes[account];
        }
    }

    private async void upload(FileTransfer file_transfer, HttpFileSendData file_send_data) throws FileSendError {
        Xmpp.XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) return;

        uint8[] buf = new uint8[256];
        Array<uint8> data = new Array<uint8>(false, true, 0);
        size_t len = -1;
        do {
            try {
                len = file_transfer.input_stream.read(buf);
            } catch (IOError e) {
                throw new FileSendError.UPLOAD_FAILED("HTTP upload: IOError reading stream: %s".printf(e.message));
            }
            data.append_vals(buf, (uint) len);
        } while(len > 0);

        Soup.Message message = new Soup.Message("PUT", file_send_data.url_up);
        message.set_request(file_transfer.mime_type, Soup.MemoryUse.COPY, data.data);
        Soup.Session session = new Soup.Session();
        try {
            yield session.send_async(message);
            if (message.status_code < 200 && message.status_code >= 300) {
                throw new FileSendError.UPLOAD_FAILED("HTTP status code %s".printf(message.status_code.to_string()));
            }
        } catch (Error e) {
            throw new FileSendError.UPLOAD_FAILED("HTTP upload error: %s".printf(e.message));
        }
    }

    private void on_stream_negotiated(Account account, XmppStream stream) {
        stream_interactor.module_manager.get_module(account, Xmpp.Xep.HttpFileUpload.Module.IDENTITY).feature_available.connect((stream, max_file_size) => {
            lock (max_file_sizes) {
                max_file_sizes[account] = max_file_size;
            }
            upload_available(account);
        });
    }

    private void check_add_oob(Entities.Message message, Xmpp.MessageStanza message_stanza, Conversation conversation) {
        if (message.encryption == Encryption.NONE && message_is_file(db, message) && message.body.has_prefix("http")) {
            Xep.OutOfBandData.add_url_to_message(message_stanza, message_stanza.body);
        }
    }

    public int get_id() { return 0; }

    public float get_priority() { return 100; }
}

}
