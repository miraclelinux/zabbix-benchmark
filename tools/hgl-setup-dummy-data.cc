#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>
using namespace std;

#include <stdint.h>
#include <stdarg.h>

#define __STDC_FORMAT_MACROS
#include <inttypes.h>

#include "history-gluon.h"

typedef bool (*command_handler_fn)(const vector<string> &args);
typedef map<string, command_handler_fn> command_map_t;
typedef command_map_t::iterator command_map_itr;

// --------------------------------------------------------------------------
// class: hgl_context
// --------------------------------------------------------------------------
class hgl_context_factory {
	string m_db_name;
	history_gluon_context_t m_ctx;
public:
	hgl_context_factory(void);
	~hgl_context_factory();
	void set_database_name(string &name);
	history_gluon_context_t get(void);
};

hgl_context_factory::hgl_context_factory(void)
: m_ctx(NULL)
{
}

hgl_context_factory::~hgl_context_factory()
{
	if (m_ctx) {
		history_gluon_free_context(m_ctx);
		m_ctx = NULL;
	}
}

void hgl_context_factory::set_database_name(string &name)
{
	m_db_name = name;
}

history_gluon_context_t hgl_context_factory::get(void)
{
	if (m_ctx)
		return m_ctx;

	history_gluon_create_context(m_db_name.c_str(), NULL, 0, &m_ctx);

	return m_ctx;
}

// --------------------------------------------------------------------------
// static variables
// --------------------------------------------------------------------------
static command_map_t           g_command_map;
static hgl_context_factory     g_hgl_ctx_factory;

// --------------------------------------------------------------------------
// static functions
// --------------------------------------------------------------------------
static bool parse_uint64(const string &value_str, uint64_t &value)
{
	const char *scan_fmt;
	if (value_str.size() > 2 && (value_str.compare(0, 2, "0x", 2) == 0))
		scan_fmt = "%"PRIx64;
	else
		scan_fmt = "%"PRIu64;

	if (sscanf(value_str.c_str(), scan_fmt, &value) < 1)
		return false;

	return true;
}

static bool add_data(const vector<string> &args, const string &value_type)
{
	if (args.size() < 5) {
		printf("Error: add_%s command needs 5 args.\n",
		       value_type.c_str());
		return false;
	}

	string db_name = args[0];
	g_hgl_ctx_factory.set_database_name(db_name);
	history_gluon_context_t ctx = g_hgl_ctx_factory.get();
	if (!ctx) {
		printf("Error: Failed to create context\n");
		return false;
	}

	uint64_t id;
	bool succeeded = parse_uint64(args[1], id);
	if (!succeeded) {
		printf("Error: failed to parse data ID: %s\n",
		       args[1].c_str());
		return false;
	}
	time_t begin_time = atoll(args[2].c_str());
	time_t end_time   = atoll(args[3].c_str());
	time_t step       = atoll(args[4].c_str());
	struct timespec ts = { tv_sec: begin_time, tv_nsec: 0 };

	for (; ts.tv_sec <= end_time; ts.tv_sec += step) {
		history_gluon_result_t result;
		if (value_type == "uint") {
			result = history_gluon_add_uint(ctx, id, &ts, 1);
		} else if (value_type == "float") {
			result = history_gluon_add_float(ctx, id, &ts, 1.0);
		} else if (value_type == "string") {
			char *data = const_cast<char*>("dummy");
			result = history_gluon_add_string(ctx, id, &ts, data);
		} else {
			printf("Error: unknown value type: %s\n",
			       value_type.c_str());
			return false;
		}
		if (result != HGL_SUCCESS) {
			printf("Error: history_gluon_add_%s: %d\n",
			       value_type.c_str(), result);
			return false;
		}
	}

	return true;
}

static bool command_handler_add_uint(const vector<string> &args)
{
	return add_data(args, "uint");
}

static bool command_handler_add_float(const vector<string> &args)
{
	return add_data(args, "float");
}

static bool command_handler_add_string(const vector<string> &args)
{
	return add_data(args, "string");
}

static void print_usage(const char *program_name)
{
	printf("Usage:\n");
	printf("\n");
	printf(" $ %s command args\n", program_name);
	printf("\n");
	printf("*** command list ***\n");
	printf("  add_uint   db_name id begin_time end_time step\n");
	printf("  add_float  db_name id begin_time end_time step\n");
	printf("  add_string db_name id begin_time end_time step\n");
	printf("\n");
}

static void init(void)
{
	g_command_map["add_uint"]   = command_handler_add_uint;
	g_command_map["add_float"]  = command_handler_add_float;
	g_command_map["add_string"] = command_handler_add_string;
}

int main(int argc, char **argv)
{
	init();

	if (argc < 2) {
		print_usage(argv[0]);
		return EXIT_FAILURE;;
	}

	char *command = argv[1];
	vector<string> args;
	for (int i = 2; i < argc; i++)
		args.push_back(argv[i]);
	command_map_itr it = g_command_map.find(command);
	if (it == g_command_map.end()) {
		printf("Error: unknown command: %s\n", command);
		return EXIT_FAILURE;
	}

	bool result = false;
	command_handler_fn command_handler = it->second;
	result = (*command_handler)(args);
	if (!result)
		return EXIT_FAILURE;

	return EXIT_SUCCESS;
}
