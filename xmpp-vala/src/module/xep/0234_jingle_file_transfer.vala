using Gee;
using Xmpp;
using Xmpp.Xep;

namespace Xmpp.Xep.JingleFileTransfer {

private const string NS_URI = "urn:xmpp:jingle:apps:file-transfer:5";

public class Module : Jingle.ContentType, XmppStreamModule {
    public static Xmpp.ModuleIdentity<Module> IDENTITY = new Xmpp.ModuleIdentity<Module>(NS_URI, "0234_jingle_file_transfer");

    public override void attach(XmppStream stream) {
        stream.get_module(ServiceDiscovery.Module.IDENTITY).add_feature(stream, NS_URI);
        stream.get_module(Jingle.Module.IDENTITY).register_content_type(this);
    }
    public override void detach(XmppStream stream) { }

    public string content_type_ns_uri() {
        return NS_URI;
    }
    public Jingle.TransportType content_type_transport_type() {
        return Jingle.TransportType.STREAMING;
    }
    public Jingle.ContentParameters parse_content_parameters(StanzaNode description) throws Jingle.IqError {
        return Parameters.parse(this, description);
    }

    public signal void file_incoming(XmppStream stream, FileTransfer file_transfer);

    public bool is_available(XmppStream stream, Jid full_jid) {
        bool? has_feature = stream.get_flag(ServiceDiscovery.Flag.IDENTITY).has_entity_feature(full_jid, NS_URI);
        if (has_feature == null || !(!)has_feature) {
            return false;
        }
        return stream.get_module(Jingle.Module.IDENTITY).is_available(stream, Jingle.TransportType.STREAMING, full_jid);
    }

    public async void offer_file_stream(XmppStream stream, Jid receiver_full_jid, InputStream input_stream, string basename, int64 size) throws IOError {
        StanzaNode description = new StanzaNode.build("description", NS_URI)
            .add_self_xmlns()
            .put_node(new StanzaNode.build("file", NS_URI)
                .put_node(new StanzaNode.build("name", NS_URI).put_node(new StanzaNode.text(basename)))
                .put_node(new StanzaNode.build("size", NS_URI).put_node(new StanzaNode.text(size.to_string()))));
                // TODO(hrxi): Add the mandatory hash field

        Jingle.Session session = stream.get_module(Jingle.Module.IDENTITY)
            .create_session(stream, Jingle.TransportType.STREAMING, receiver_full_jid, Jingle.Senders.INITIATOR, "a-file-offer", description); // TODO(hrxi): Why "a-file-offer"?

        SourceFunc callback = offer_file_stream.callback;
        session.accepted.connect((stream) => {
            session.conn.input_stream.close();
            Idle.add((owned) callback);
        });
        yield;

        // TODO(hrxi): catch errors
        yield session.conn.output_stream.splice_async(input_stream, OutputStreamSpliceFlags.CLOSE_SOURCE|OutputStreamSpliceFlags.CLOSE_TARGET);
    }

    public override string get_ns() { return NS_URI; }
    public override string get_id() { return IDENTITY.id; }
}

public class Parameters : Jingle.ContentParameters, Object {

    Module parent;
    string? media_type;
    public string? name { get; private set; }
    public int64 size { get; private set; }
    public StanzaNode original_description { get; private set; }

    public Parameters(Module parent, StanzaNode original_description, string? media_type, string? name, int64? size) {
        this.parent = parent;
        this.original_description = original_description;
        this.media_type = media_type;
        this.name = name;
        this.size = size;
    }

    public static Parameters parse(Module parent, StanzaNode description) throws Jingle.IqError {
        Gee.List<StanzaNode> files = description.get_subnodes("file", NS_URI);
        if (files.size != 1) {
            throw new Jingle.IqError.BAD_REQUEST("there needs to be exactly one file node");
        }
        StanzaNode file = files[0];
        StanzaNode? media_type_node = file.get_subnode("media-type", NS_URI);
        StanzaNode? name_node = file.get_subnode("name", NS_URI);
        StanzaNode? size_node = file.get_subnode("size", NS_URI);
        string? media_type = media_type_node != null ? media_type_node.get_string_content() : null;
        string? name = name_node != null ? name_node.get_string_content() : null;
        string? size_raw = size_node != null ? size_node.get_string_content() : null;
        // TODO(hrxi): For some reason, the ?:-expression does not work due to a type error.
        //int64? size = size_raw != null ? int64.parse(size_raw) : null; // TODO(hrxi): this has no error handling
        int64 size = -1;
        if (size_raw != null) {
            size = int64.parse(size_raw);
            if (size < 0) {
                throw new Jingle.IqError.BAD_REQUEST("negative file size is invalid");
            }
        }

        return new Parameters(parent, description, media_type, name, size);
    }

    public void on_session_initiate(XmppStream stream, Jingle.Session session) {
        parent.file_incoming(stream, new FileTransfer(session, this));
    }
}

public class FileTransfer : Object {
    Jingle.Session session;
    Parameters parameters;

    public Jid peer { get { return session.peer_full_jid; } }
    public string? file_name { get { return parameters.name; } }
    public int64 size { get { return parameters.size; } }

    public InputStream? stream { get { return session.conn != null ? session.conn.input_stream : null; } }

    public FileTransfer(Jingle.Session session, Parameters parameters) {
        this.session = session;
        this.parameters = parameters;
    }

    public void accept(XmppStream stream) {
        session.accept(stream, parameters.original_description);
        session.conn.output_stream.close();
    }

    public void reject(XmppStream stream) {
        session.reject(stream);
    }
}

}
